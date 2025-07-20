//
//  RequestsView.swift
//  HarborExample
//
//  Created by Javier Manzo on 31/07/2024.
//

import SwiftUI
import HarborJRPC
import Harbor

struct RequestsView: View {
    @State private var results: [String] = []

    init() {
        Task { await HarborJRPC.setURL("https://ethereum.publicnode.com") }
    }

    var body: some View {
        VStack(spacing: 20) {
            Button("REST Request") {
                requestREST()
            }.buttonStyle(.borderedProminent)

            Button("JRPC Request") {
                requestJRPC()
            }.buttonStyle(.borderedProminent)
            
            Button("REST Stream (Cache + Remote)") {
                requestRESTStream()
            }
            .buttonStyle(.borderedProminent)
            
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Results:")
                        .font(.headline)
                    
                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        HStack(alignment: .top) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(result)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                Button("Clear Results") {
                    results.removeAll()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
    }

    func requestREST() {
        results.removeAll()
        Task {
            let response = await RESTRequest().request()

            let resultText: String
            switch response {
            case .success(let result):
                resultText = "🌐 REST: \"\(result.quote)\""
            case .error(let error):
                resultText = "❌ REST Error: \(error)"
            }

            await MainActor.run {
                results.append(resultText)
            }
        }
    }
    
    func requestRESTStream() {
        results.removeAll()
        Task {
            do {
                for try await (response, origin) in RESTRequest().requestStream() {
                    let originText = origin == .cache ? "📱 Cache" : "🌐 Remote"
                    let resultText = "\(originText): \"\(response.quote)\""
                    
                    await MainActor.run {
                        results.append(resultText)
                    }
                }
            } catch {
                await MainActor.run {
                    results.append("❌ Stream Error: \(error)")
                }
            }
        }
    }
    
    func requestJRPC() {
        results.removeAll()
        Task {
            let response = await JRPCRequest().request()

            let resultText: String
            switch response {
            case .success(let result):
                resultText = "⚡ JRPC: \(result)"
            case .error(let error):
                resultText = "❌ JRPC Error: \(error)"
            }

            await MainActor.run {
                results.append(resultText)
            }
        }
    }
}

#Preview {
    RequestsView()
}
