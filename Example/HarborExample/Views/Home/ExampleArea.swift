//
//  ExampleArea.swift
//  HarborExample
//
//  The areas of Harbor listed on the home screen, each one a screen of its own
//

import SwiftUI

enum ExampleArea: CaseIterable, Identifiable {
    case rest, data, resilience, realtime, images, security, tooling

    var id: Self { self }

    var title: String {
        switch self {
        case .rest: return "REST requests"
        case .data: return "Data"
        case .resilience: return "Auth and resilience"
        case .realtime: return "JSON-RPC and WebSocket"
        case .images: return "Images"
        case .security: return "Security"
        case .tooling: return "Testing and debugging"
        }
    }

    var subtitle: String {
        switch self {
        case .rest: return "GET, POST, PUT, PATCH and DELETE"
        case .data: return "Caching, streaming and pagination"
        case .resilience: return "Authentication, headers and retries"
        case .realtime: return "Protocols beyond plain REST"
        case .images: return "Loading, processing and caching"
        case .security: return "mTLS and SSL pinning"
        case .tooling: return "Mocks and request logging"
        }
    }

    var icon: String {
        switch self {
        case .rest: return "arrow.up.arrow.down.circle"
        case .data: return "externaldrive"
        case .resilience: return "lock.rotation"
        case .realtime: return "bolt.horizontal.circle"
        case .images: return "photo.on.rectangle.angled"
        case .security: return "checkmark.shield"
        case .tooling: return "theatermasks"
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .rest: RESTGroup()
        case .data: DataGroup()
        case .resilience: ResilienceGroup()
        case .realtime: RealtimeGroup()
        case .images: ImagesView()
        case .security: SecurityGroup()
        case .tooling: ToolingGroup()
        }
    }
}

// MARK: - Row

struct ExampleAreaRow: View {
    let area: ExampleArea

    var body: some View {
        NavigationLink(destination: area.destination) {
            HStack(spacing: 16) {
                Image(systemName: area.icon)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 36)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.primary)
                    Text(area.subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color.gray.opacity(0.5))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}
