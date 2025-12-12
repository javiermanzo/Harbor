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
    private let sslPinningKeys: [String]?

    private let clientIdentityResult: Result<SecIdentity, Error>?

    init(mTLS: HmTLS?, sslPinningKeys: [String]?) {
        self.mTLS = mTLS
        self.sslPinningKeys = sslPinningKeys
        
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
            if let sslPinningKeys, let result = processSSLPinning(challenge, sslPinningKeys: sslPinningKeys) {
                return completionHandler(result.disposition, result.credential)
            }
            // If SSL pinning is configured but validation fails, reject
            if sslPinningKeys != nil {
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

    private func processSSLPinning(_ challenge: URLAuthenticationChallenge, sslPinningKeys: [String]) -> HChallengeResult? {
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
        
        // Check if any certificate in the chain matches one of the pinned keys
        let chainCount = SecTrustGetCertificateCount(serverTrust)
        
        for index in 0..<chainCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index),
                  let publicKey = SecCertificateCopyKey(certificate) else {
                continue
            }
            
            var keyError: Unmanaged<CFError>?
            guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &keyError) as Data? else {
                if let error = keyError?.takeRetainedValue() {
                    Self.logger.log("Failed to extract public key data: \(error)", level: .error)
                }
                continue
            }
            
            let publicKeyHash = SHA256.sha256(data: publicKeyData)
            
            if sslPinningKeys.contains(publicKeyHash) {
                let credential = URLCredential(trust: serverTrust)
                return HChallengeResult(.useCredential, credential)
            }
        }

        // SSL pinning failed - reject connection
        Self.logger.log("SSL Pinning Failed: Public Key hash mismatch", level: .error)
        return (disposition: .cancelAuthenticationChallenge, credential: nil)
    }
}
