//
//  RequestsView.swift
//  HarborExample
//
//  Complete example demonstrating all Harbor features
//

import SwiftUI
import HarborJRPC
import HarborWebSocket
import Harbor
import LogBird

struct RequestsView: View {
    @State var results: [String] = []
    @State var isLoading: Bool = false
    @State var isSettingsPresented: Bool = false

    // Values shown in the settings sheet (Harbor's defaults, or what the sheet applied last).
    @State var timeoutInterval: Double = 15
    @State var isLoggingEnabled: Bool = true
    @State var cacheTypeIndex: Int = 0

    // Static logger using LogBird
    static let logger = LogBird(subsystem: "com.harbor.example", category: "RequestsView")

    // Auth providers are actors (not `ObservableObject`s), so `@State` keeps one instance alive
    // across SwiftUI render passes.
    // Auth provider for authenticated requests
    @State var authProvider = TokenAuthProvider()

    // Auth provider for the token-refresh demo (starts with an expired token)
    @State var refreshAuthProvider = RefreshingAuthProvider()

    // Survives view re-creation; `RequestsView` is `@MainActor` (SwiftUI `View`), so the
    // flag is isolated to the main actor as well.
    @MainActor static var isHarborSetup = false
    @State var isMocksEnabled: Bool = false

    // The open WebSocket connection of the WebSocket demo, kept across render passes.
    @State var webSocket: HWebSocket?

    func setupOnAppear() {
        Self.logger.log("setupOnAppear called", level: .info)
        Task {
            let mocks = await Harbor.mocksEnabled
            await MainActor.run {
                self.isMocksEnabled = mocks
            }
            await setupHarbor()
            Self.logger.log("setupHarbor completed", level: .info)
        }
    }

    private func setupHarbor() async {
        guard !Self.isHarborSetup else { return }
        Self.isHarborSetup = true

        // Set default headers for all requests
        await Harbor.setDefaultHeaderParameters([
            "X-Client-Version": "1.0.0",
            "X-Client-Platform": "iOS"
        ])

        // Set default cache type (the settings sheet starts on `.urlCache()`)
        await Harbor.setDefaultCacheType(.urlCache())

        // Enable debug logging (the settings sheet starts with logging on)
        await Harbor.setLoggingEnabled(true)

        // Configure JRpc
        await HarborJRPC.configure(url: URL(string: "https://ethereum.publicnode.com")!)

        // mTLS is configured on demand by the "GET - With mTLS" demo.
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            // MARK: - Basic Requests Section
                            ExampleSection(title: "Basic GET Requests") {
                                ExampleButton(title: "GET - Simple Request", icon: "arrow.down.circle") { performBasicGet() }
                                ExampleButton(title: "GET - With Path Parameter", icon: "arrow.right.circle") { performGetWithPathParameter() }
                                ExampleButton(title: "GET - With Query Params", icon: "magnifyingglass") { performGetWithQueryParams() }
                            }

                            // MARK: - POST Requests
                            ExampleSection(title: "POST Requests") {
                                ExampleButton(title: "POST - Create Resource", icon: "plus.circle") { performPostRequest() }
                                ExampleButton(title: "POST - Encodable rawBody", icon: "doc.plaintext") { performRawBodyPost() }
                                ExampleButton(title: "POST - Multipart Upload", icon: "paperclip") { performMultipartPost() }
                            }

                            // MARK: - PUT & PATCH
                            ExampleSection(title: "PUT & PATCH") {
                                ExampleButton(title: "PUT - Full Update", icon: "arrow.triangle.2.circlepath") { performPutRequest() }
                                ExampleButton(title: "PATCH - Partial Update", icon: "pencil") { performPatchRequest() }
                            }

                            // MARK: - DELETE
                            ExampleSection(title: "DELETE") {
                                ExampleButton(title: "DELETE - Remove Resource", icon: "trash", isDestructive: true) { performDeleteRequest() }
                            }

                            // MARK: - Caching
                            ExampleSection(title: "Caching") {
                                ExampleButton(title: "GET - With Custom Cache", icon: "externaldrive") { performCachedRequest() }
                                ExampleButton(title: "GET - With URLCache (ETags)", icon: "network") { performURLCacheRequest() }
                                ExampleButton(title: "GET - Cache Only", icon: "internaldrive") { performCacheOnlyRequest() }
                                ExampleButton(title: "Clear All Cache", icon: "xmark.circle", isDestructive: true) { clearAllCache() }
                            }

                            // MARK: - Streaming
                            ExampleSection(title: "Streaming") {
                                ExampleButton(title: "Stream - Cache + Remote", icon: "arrow.triangle.2.circlepath.circle") { performStreamRequest() }
                                ExampleButton(title: "Stream - Cache Only", icon: "internaldrive") { performStreamCacheOnlyRequest() }
                                ExampleButton(title: "Stream - Remote Only", icon: "antenna.radiowaves.left.and.right") { performStreamRemoteOnlyRequest() }
                            }

                            // MARK: - Pagination
                            ExampleSection(title: "Pagination") {
                                ExampleButton(title: "GET - Paginated", icon: "number") { performPaginatedRequest() }
                            }

                            // MARK: - Authentication
                            ExampleSection(title: "Authentication") {
                                ExampleButton(title: "GET - With Auth", icon: "lock.shield") { performAuthenticatedRequest() }
                                ExampleButton(title: "GET - Auth with Token Refresh", icon: "lock.rotation") { performAuthWithRefresh() }
                            }

                            // MARK: - Headers
                            ExampleSection(title: "Custom Headers") {
                                ExampleButton(title: "GET - Custom Headers", icon: "header") { performRequestWithHeaders() }
                            }

                            // MARK: - Retry
                            ExampleSection(title: "Retry Logic") {
                                ExampleButton(title: "GET - With Retry (3x)", icon: "arrow.clockwise.circle") { performRequestWithRetry() }
                            }

                            // MARK: - JSON-RPC
                            ExampleSection(title: "JSON-RPC (Ethereum)") {
                                ExampleButton(title: "JRPC - Block Number", icon: "bitcoinsign.circle") { performJRPCRequest() }
                                ExampleButton(title: "JRPC - Get Balance", icon: "dollarsign.circle") { performJRPCBalanceRequest() }
                                ExampleButton(title: "JRPC - Batch", icon: "square.stack.3d.up") { performJRPCBatchRequest() }
                            }

                            // MARK: - WebSocket
                            ExampleSection(title: "WebSocket (Echo)") {
                                ExampleButton(title: "WebSocket - Connect", icon: "bolt.horizontal.circle") { connectWebSocket() }
                                ExampleButton(title: "WebSocket - Send Message", icon: "paperplane.circle") { sendWebSocketMessage() }
                                ExampleButton(title: "WebSocket - Close", icon: "xmark.circle", isDestructive: true) { closeWebSocket() }
                            }

                            // MARK: - mTLS
                            ExampleSection(title: "Security (mTLS)") {
                                ExampleButton(title: "GET - With mTLS", icon: "lock.icloud") { performMTLSRequest() }
                                ExampleButton(title: "Configure SSL Pinning", icon: "checkmark.shield") { configureSSLPinning() }
                            }

                            // MARK: - Mocking
                            ExampleSection(title: "Mocking") {
                                Toggle(isOn: $isMocksEnabled) {
                                    HStack {
                                        Image(systemName: "theatermasks")
                                            .frame(width: 24)
                                        Text("Enable Mocks")
                                    }
                                }
                                .padding()
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(12)
                                .onChange(of: isMocksEnabled) { newValue in
                                    Task {
                                        await Harbor.setMocksEnabled(newValue)
                                    }
                                }

                                ExampleButton(title: "Register Mock Response", icon: "text.badge.plus") { registerMock() }
                                ExampleButton(title: "Clear Mocks", icon: "trash", isDestructive: true) { 
                                    Task {
                                        await Harbor.removeAllMocks()
                                        await MainActor.run {
                                            addResult("All mocks removed")
                                        }
                                    }
                                }
                            }

                            // MARK: - Debug
                            ExampleSection(title: "Debug Mode") {
                                ExampleButton(title: "GET - Debug Mode", icon: "antenna.radiowaves.left.and.right") { performDebugRequest() }
                            }

                            Spacer(minLength: 40)
                        }
                        .padding()
                    }

                    // MARK: - Sticky Results Console
                    ResultsConsoleView(results: results) {
                        withAnimation {
                            results.removeAll()
                        }
                    }
                }
            }
            .onAppear {
                setupOnAppear()
            }
            .onDisappear {
                // Close the demo connection with the view; its reader task then ends too.
                let socket = webSocket
                Task { await socket?.close(code: .goingAway) }
            }
            .navigationTitle("Harbor Examples")
            .navigationBarItems(trailing:
                Button(action: { isSettingsPresented = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .semibold))
                }
            )
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(
                    timeoutInterval: $timeoutInterval,
                    isLoggingEnabled: $isLoggingEnabled,
                    cacheTypeIndex: $cacheTypeIndex
                )
            }
        }
        .overlay {
            if isLoading {
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
    }

    // MARK: - Helpers

    /// Runs an async operation toggling the loading overlay.
    func performWithLoading(_ operation: @escaping @MainActor () async -> Void) {
        isLoading = true
        Task {
            await operation()
            isLoading = false
        }
    }

    func addResult(_ text: String) {
        results.append(text)
    }
}

#Preview {
    RequestsView()
}
