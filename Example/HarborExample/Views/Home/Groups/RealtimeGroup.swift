//
//  RealtimeGroup.swift
//  HarborExample
//
//  Screen of the "JSON-RPC and WebSocket" area
//

import SwiftUI

struct RealtimeGroup: View {
    private let area = ExampleArea.realtime

    var body: some View {
        ExampleScreen(subtitle: area.subtitle) {
            JSONRPCSection()
            WebSocketSection()
        }
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
