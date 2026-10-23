//
//  RequestsView+Security.swift
//  HarborExample
//
//  mTLS and SSL pinning
//

import SwiftUI
import Harbor

// MARK: - mTLS and SSL pinning
extension RequestsView {
    func performMTLSRequest() {
        addResult("=== mTLS Request ===")
        performWithLoading {
            // Load the client certificate bundled with the app and configure mTLS.
            guard let p12URL = Bundle.main.url(forResource: "certificate", withExtension: "p12") else {
                await MainActor.run {
                    addResult("certificate.p12 not found in the app bundle")
                }
                return
            }

            do {
                // Scope the client identity to the mTLS test host so it is never offered elsewhere.
                let mTLS = HMTLS(p12FileUrl: p12URL, hosts: ["certauth.cryptomix.com"]) { "notapassword" }
                try await Harbor.setMTLS(mTLS)
            } catch {
                let message: String
                if let mtlsError = error as? HMTLSError {
                    switch mtlsError {
                    case .fileNotFound:
                        message = "certificate.p12 could not be read"
                    case .passwordProviderFailed:
                        message = "the P12 password could not be supplied"
                    case .invalidPassword:
                        message = "the P12 password was rejected"
                    case .invalidP12Format:
                        message = "certificate.p12 is malformed"
                    case .noIdentity:
                        message = "certificate.p12 contains no identity"
                    }
                } else {
                    message = error.localizedDescription
                }
                await MainActor.run {
                    addResult("Could not configure mTLS: \(message)")
                }
                return
            }

            await MainActor.run {
                addResult("Client identity loaded from certificate.p12")
            }

            let response = await MTLSRequest().request()

            await MainActor.run {
                switch response {
                case .success(let result):
                    addResult("mTLS successful!")
                    addResult("Secure connection established with client certificate.")
                    addResult("Identity: \(result.sslClientSDN ?? "Unknown")")
                case .error(let error):
                    if case .timeout = error {
                        addResult("Request timed out.")
                        addResult("Note: The public test server is frequently offline.")
                        addResult("However, your client certificate was loaded and Harbor is configured correctly.")
                    } else {
                        addResult("MTLS Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func configureSSLPinning() {
        addResult("=== Configuring SSL Pinning ===")
        performWithLoading {
            let host = "jsonplaceholder.typicode.com"
            do {
                // Read the live server certificate and compute its pin.
                let certificate = try await ServerCertificateFetcher.fetchCertificate(from: host)
                guard let pin = await Harbor.computePin(for: certificate) else {
                    await MainActor.run {
                        addResult("Could not compute a pin for the server certificate")
                    }
                    return
                }
                await MainActor.run {
                    addResult("Computed pin: \(pin)")
                }

                // Pin only the demo host; other endpoints keep default validation.
                await Harbor.setSSLPinningKeys([pin], forHosts: [host])

                // Verify that a pinned request to the host succeeds.
                let response = await GetPinnedUsersRequest().request()
                await MainActor.run {
                    switch response {
                    case .success(let users):
                        addResult("Pinned request to \(host) succeeded (\(users.count) users)")
                    case .error(let error):
                        addResult("Pinned request failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run {
                    addResult("Could not fetch the server certificate: \(error.localizedDescription)")
                }
            }
        }
    }
}
