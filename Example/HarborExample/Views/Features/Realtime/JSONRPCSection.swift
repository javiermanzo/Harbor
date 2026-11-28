//
//  JSONRPCSection.swift
//  HarborExample
//
//  JSON-RPC 2.0 calls against an Ethereum node: single, with params and batch.
//

import SwiftUI
import HarborJRPC
import Harbor

struct JSONRPCSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    var body: some View {
        ExampleSection(title: "JSON-RPC (Ethereum)") {
            ExampleButton(title: "JRPC - Block Number", icon: "bitcoinsign.circle") { performJRPCRequest() }
            ExampleButton(title: "JRPC - Get Balance", icon: "dollarsign.circle") { performJRPCBalanceRequest() }
            ExampleButton(title: "JRPC - Batch", icon: "square.stack.3d.up") { performJRPCBatchRequest() }
        }
    }

    // MARK: - Actions

    private func performJRPCRequest() {
        runner.log("=== JRPC - eth_blockNumber ===")
        runner.run {
            let response = await JRPCRequest().requestResult()

            await MainActor.run {
                switch response {
                case .success(let blockNumber):
                    runner.log("Current block: \(blockNumber)")
                case .error(let jrpcError):
                    runner.log("JRPC Error: \(jrpcError.localizedDescription)")
                }
            }
        }
    }

    private func performJRPCBalanceRequest() {
        runner.log("=== JRPC - eth_getBalance ===")
        runner.run {
            let request = GetBalanceRequest(address: "0x742d35cc6634c0532925a3b844bc454e4438f44e")
            let response = await request.requestResult()

            await MainActor.run {
                switch response {
                case .success(let balance):
                    runner.log("Balance: \(balance)")
                case .error(let jrpcError):
                    runner.log("JRPC Error: \(jrpcError.localizedDescription)")
                }
            }
        }
    }

    private func performJRPCBatchRequest() {
        runner.log("=== JRPC - Batch (blockNumber + getBalance) ===")
        runner.run {
            do {
                // One HTTP call carrying both requests; each response is paired with its id.
                let responses = try await HarborJRPC.batch([
                    JRPCRequest(),
                    GetBalanceRequest(address: "0x742d35cc6634c0532925a3b844bc454e4438f44e")
                ])

                await MainActor.run {
                    runner.log("Batch returned \(responses.count) responses")
                    for response in responses {
                        switch response {
                        case .success(_, let result):
                            runner.log("Result: \(result)")
                        case .error(_, let error):
                            runner.log("JRPC Error: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    runner.log("JRPC Batch Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
