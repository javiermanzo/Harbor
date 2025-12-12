//
//  HURLSessionDelegate.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation
import LogBird
import Security

final class HURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    typealias HChallengeResult = (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?)

    /// Logger instance for SSL/TLS related events
    private static let logger = LogBird(subsystem: "com.harbor", category: "ssl")

    private let mTLS: HmTLS?
    private let sslPinningSHA256: String?

    private let clientIdentityResult: Result<SecIdentity, Error>?

    init(mTLS: HmTLS?, sslPinningSHA256: String?) {
        self.mTLS = mTLS
        self.sslPinningSHA256 = sslPinningSHA256
        
        if let mTLS {
            self.clientIdentityResult = Result {
                let p12Data = try Data(contentsOf: mTLS.p12FileUrl)
                let p12Contents = PKCS12(p12Data: p12Data, password: mTLS.password)
                
                guard let identity = p12Contents.identity else {
                    throw HRequestError.sslError
                }
                return identity
            }
        } else {
            self.clientIdentityResult = nil
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Handle client certificate authentication (mTLS)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            if let result = processCertificateChallenge(challenge) {
                return completionHandler(result.disposition, result.credential)
            }
            // If mTLS is not configured but client cert is requested, cancel
            return completionHandler(.cancelAuthenticationChallenge, nil)
        }

        // Handle server trust validation (SSL pinning)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let sslPinningSHA256, let result = processSSLPinning(challenge, sslPinningSHA256: sslPinningSHA256) {
                return completionHandler(result.disposition, result.credential)
            }
            // If SSL pinning is configured but validation fails, reject
            if sslPinningSHA256 != nil {
                return completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }

        // Default handling for other authentication methods
        return completionHandler(.performDefaultHandling, nil)
    }

    private func processCertificateChallenge(_ challenge: URLAuthenticationChallenge) -> HChallengeResult? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
            return nil
        }
        
        guard let result = clientIdentityResult else {
            return nil
        }
        
        switch result {
        case .success(let identity):
            let credential = URLCredential(identity: identity,
                                           certificates: nil,
                                           persistence: .none)
            return HChallengeResult(disposition: .useCredential, credential: credential)
            
        case .failure(let error):
            Self.logger.log("Failed to load certificate: \(error)", level: .error)
            return (disposition: .cancelAuthenticationChallenge, credential: nil)
        }
    }

    private func processSSLPinning(_ challenge: URLAuthenticationChallenge, sslPinningSHA256: String) -> HChallengeResult? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return nil
        }
        
        // Evaluate server trust first
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            if let error = error {
                Self.logger.log("SSL Trust Evaluation Failed", error: error, level: .error)
            }
            return (disposition: .cancelAuthenticationChallenge, credential: nil)
        }
        
        // Get certificate chain for pinning validation
        guard let trustCertificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              !trustCertificateChain.isEmpty else {
            Self.logger.log("SSL Pinning Failed: Unable to get certificate chain", level: .error)
            return (disposition: .cancelAuthenticationChallenge, credential: nil)
        }

        // Check if any certificate in the chain matches the pinned hash
        for serverCertificate in trustCertificateChain {
            let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data
            let serverCertificateHash = SHA256.sha256(data: serverCertificateData)

            if serverCertificateHash == sslPinningSHA256 {
                let credential = URLCredential(trust: serverTrust)
                return HChallengeResult(.useCredential, credential)
            }
        }

        // SSL pinning failed - reject connection
        Self.logger.log("SSL Pinning Failed: Certificate hash mismatch", level: .error)
        return (disposition: .cancelAuthenticationChallenge, credential: nil)
    }
}
