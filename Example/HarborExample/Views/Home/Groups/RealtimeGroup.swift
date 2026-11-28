//
//  RealtimeGroup.swift
//  HarborExample
//
//  JSON-RPC and WebSocket.
//

import SwiftUI

struct RealtimeGroup: View {
    var body: some View {
        ExampleGroup(title: "JSON-RPC and WebSocket", subtitle: "Protocols beyond plain REST.") {
            JSONRPCSection()
            WebSocketSection()
        }
    }
}
