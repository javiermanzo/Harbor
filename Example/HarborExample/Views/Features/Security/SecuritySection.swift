//
//  SecuritySection.swift
//  HarborExample
//
//  mTLS with a bundled client identity and SSL pinning.
//

import SwiftUI
import Harbor

struct SecuritySection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "Security (mTLS)") {
            ExampleButton(title: "GET - With mTLS", icon: "lock.icloud") { performMTLSRequest() }
            ExampleButton(title: "Configure SSL Pinning", icon: "checkmark.shield") { configureSSLPinning() }
        }
    }

    // MARK: - Actions

    private func performMTLSRequest() {
        runner.log("=== mTLS Request ===")
        runner.run {
            // Load the client certificate bundled with the app and configure mTLS.
            guard let p12URL = Bundle.main.url(forResource: "certificate", withExtension: "p12") else {
                await MainActor.run {
                    runner.log("certificate.p12 not found in the app bundle")
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
                    runner.log("Could not configure mTLS: \(message)")
                }
                return
            }

            await MainActor.run {
                runner.log("Client identity loaded from certificate.p12")
            }

            let response = await MTLSRequest().request()

            await MainActor.run {
                switch response {
                case .success(let result):
                    runner.log("mTLS successful!")
                    runner.log("Secure connection established with client certificate.")
                    runner.log("Identity: \(result.sslClientSDN ?? "Unknown")")
                case .error(let error):
                    if case .timeout = error {
                        runner.log("Request timed out.")
                        runner.log("Note: The public test server is frequently offline.")
                        runner.log("However, your client certificate was loaded and Harbor is configured correctly.")
                    } else {
                        runner.log("MTLS Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func configureSSLPinning() {
        runner.log("=== Configuring SSL Pinning ===")
        runner.run {
            let host = "jsonplaceholder.typicode.com"
            do {
                // Read the live server certificate and compute its pin.
                let certificate = try await ServerCertificateFetcher.fetchCertificate(from: host)
                guard let pin = await Harbor.computePin(for: certificate) else {
                    await MainActor.run {
                        runner.log("Could not compute a pin for the server certificate")
                    }
                    return
                }
                await MainActor.run {
                    runner.log("Computed pin: \(pin)")
                }

                // Pin only the demo host; other endpoints keep default validation.
                await Harbor.setSSLPinningKeys([pin], forHosts: [host])

                // Verify that a pinned request to the host succeeds.
                let response = await GetPinnedUsersRequest().request()
                await MainActor.run {
                    switch response {
                    case .success(let users):
                        runner.log("Pinned request to \(host) succeeded (\(users.count) users)")
                    case .error(let error):
                        runner.log("Pinned request failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run {
                    runner.log("Could not fetch the server certificate: \(error.localizedDescription)")
                }
            }
        }
    }
}
