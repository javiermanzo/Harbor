//
//  RequestsView.swift
//  HarborExample
//
//  Created by Javier Manzo on 31/07/2024.
//

import SwiftUI
import HarborJRPC

struct RequestsView: View {
    @State private var alertText = ""
    @State private var showAlert = false

    init() {
        Task { await HarborJRPC.setURL("https://rpc.ankr.com/eth") }
    }

    var body: some View {
        VStack {
            Button("REST Request") {
                requestREST()
            }.buttonStyle(.borderedProminent)

            Button("JRPC Request") {
                requestJRPC()
            }.buttonStyle(.borderedProminent)
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Request Info"), message: Text(alertText), dismissButton: .default(Text("OK")))
        }
        .padding()
    }

    func requestREST() {
        Task {
            let response = await RESTRequest().request()

            switch response {
            case .success(let result):
                alertText = result.quote
            case .cancelled:
                alertText = "Request Cancelled"
            case .error:
                alertText = "Request Error"
            }

            await MainActor.run {
                showAlert = true
            }
        }
    }
    func requestJRPC() {
        Task {
            let response = await JRPCRequest().request()

            switch response {
            case .success(let result):
                alertText = result
            case .cancelled:
                alertText = "Request Cancelled"
            case .error(let error):
                alertText = "Request Error \(error.localizedDescription)"
            }

            await MainActor.run {
                showAlert = true
            }
        }
    }
}

#Preview {
    RequestsView()
}
