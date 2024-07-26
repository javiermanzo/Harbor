//
//  HURLSessionDelegate.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation

final class HURLSessionDelegate: NSObject, URLSessionDelegate {

    typealias HChallengeResult = (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?)

    private let mTLS: HmTLS?
    private let sslPinningSHA256: String?

    init(mTLS: HmTLS?, sslPinningSHA256: String?) {
        self.mTLS = mTLS
        self.sslPinningSHA256 = sslPinningSHA256
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate,
           let mTLS,
           let result = processCertificateChallenge(challenge, mTLS: mTLS) {
            return completionHandler(result.disposition, result.credential)
        }

        if challenge.protectionSpace.serverTrust != nil,
           let sslPinningSHA256,
           let result = processSSLPinning(challenge, sslPinningSHA256: sslPinningSHA256) {
            return completionHandler(result.disposition, result.credential)
        }

        return completionHandler(.performDefaultHandling, nil)
    }

    private func processCertificateChallenge(_ challenge: URLAuthenticationChallenge, mTLS: HmTLS) -> HChallengeResult? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate,
              let p12Data = try? Data(contentsOf: mTLS.p12FileUrl) else {
            return nil
        }

        let p12Contents = PKCS12(p12Data: p12Data, password: mTLS.password)

        guard let identity = p12Contents.identity else {
            return (disposition: .performDefaultHandling, credential: nil)
        }

        let credential = URLCredential(identity: identity,
                                       certificates: nil,
                                       persistence: .none)

        challenge.sender?.use(credential, for: challenge)

        return HChallengeResult(disposition: .useCredential, credential: credential)
    }

    private func processSSLPinning(_ challenge: URLAuthenticationChallenge, sslPinningSHA256: String) -> HChallengeResult? {
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              let trustCertificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              !trustCertificateChain.isEmpty
        else {
            return nil
        }

        for serverCertificate in trustCertificateChain {
            let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data
            let serverCertificateHash = SHA256.sha256(data: serverCertificateData)

            if serverCertificateHash == sslPinningSHA256 {
                let credential = URLCredential(trust: serverTrust)
                return HChallengeResult(.useCredential, credential)
            }
        }

        return nil
    }
}
