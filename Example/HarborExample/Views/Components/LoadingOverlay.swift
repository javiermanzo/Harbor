//
//  LoadingOverlay.swift
//  HarborExample
//
//  Full-screen spinner shown while a demo request runs
//

import SwiftUI

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Loading...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color(.systemGray6).opacity(0.3).blur(radius: 10))
            .background(Color.black.opacity(0.5))
            .cornerRadius(16)
        }
    }
}
