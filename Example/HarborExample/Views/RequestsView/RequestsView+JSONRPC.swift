//
//  RequestsView+JSONRPC.swift
//  HarborExample
//
//  JSON-RPC requests
//

import SwiftUI
import HarborJRPC
import HarborWebSocket
import Harbor
import LogBird

// MARK: - JSON-RPC requests
extension RequestsView {
    func performJRPCRequest() {
        addResult("=== JRPC - eth_blockNumber ===")
        performWithLoading {
            let response = await JRPCRequest().requestResult()

            await MainActor.run {
                switch response {
                case .success(let blockNumber):
                    addResult("Current block: \(blockNumber)")
                case .error(let jrpcError):
                    addResult("JRPC Error: \(jrpcError.localizedDescription)")
                }
            }
        }
    }

    func performJRPCBalanceRequest() {
        addResult("=== JRPC - eth_getBalance ===")
        performWithLoading {
            let request = GetBalanceRequest(address: "0x742d35cc6634c0532925a3b844bc454e4438f44e")
            let response = await request.requestResult()

            await MainActor.run {
                switch response {
                case .success(let balance):
                    addResult("Balance: \(balance)")
                case .error(let jrpcError):
                    addResult("JRPC Error: \(jrpcError.localizedDescription)")
                }
            }
        }
    }

    func performJRPCBatchRequest() {
        addResult("=== JRPC - Batch (blockNumber + getBalance) ===")
        performWithLoading {
            do {
                // One HTTP call carrying both requests; each response is paired with its id.
                let responses = try await HarborJRPC.batch([
                    JRPCRequest(),
                    GetBalanceRequest(address: "0x742d35cc6634c0532925a3b844bc454e4438f44e")
                ])

                await MainActor.run {
                    addResult("Batch returned \(responses.count) responses")
                    for response in responses {
                        switch response {
                        case .success(_, let result):
                            addResult("Result: \(result)")
                        case .error(_, let error):
                            addResult("JRPC Error: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    addResult("JRPC Batch Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
