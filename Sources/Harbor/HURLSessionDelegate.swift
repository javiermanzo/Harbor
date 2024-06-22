//
//  HURLSessionDelegate.swift
//
//
//  Created by Javier Manzo on 19/06/2024.
//

import Foundation

final class HURLSessionDelegate: NSObject, URLSessionDelegate {

    private let mTLS: HmTLS

    init(mTLS: HmTLS) {
        self.mTLS = mTLS
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        let result = processChallenge(challenge)
        completionHandler(result.disposition, result.credential)
    }

    private func processChallenge(_ challenge: URLAuthenticationChallenge) -> (disposition: URLSession.AuthChallengeDisposition, credential: URLCredential?) {
        if challenge.protectionSpace.authenticationMethod != NSURLAuthenticationMethodClientCertificate {
            return (disposition: .performDefaultHandling, credential: nil)
        }

        guard let p12Data = try? Data(contentsOf: mTLS.p12FileUrl) else {
            return (disposition: .performDefaultHandling, credential: nil)
        }

        let p12Contents = PKCS12(p12Data: p12Data, password: mTLS.password)

        guard let identity = p12Contents.identity else {
            return (disposition: .performDefaultHandling, credential: nil)
        }

        let credential = URLCredential(identity: identity,
                                       certificates: nil,
                                       persistence: .none)

        challenge.sender?.use(credential, for: challenge)

        return (disposition: .useCredential, credential: credential)
    }
}
