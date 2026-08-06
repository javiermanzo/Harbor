//
//  RequestsView.swift
//  HarborExample
//
//  Complete example demonstrating all Harbor features
//

import SwiftUI
import HarborJRPC
import Harbor
import LogBird

struct RequestsView: View {
    @State private var results: [String] = []
    @State private var isLoading: Bool = false
    @State private var isSettingsPresented: Bool = false

    // Static logger using LogBird
    private static let logger = LogBird(subsystem: "com.harbor.example", category: "RequestsView")

    // Auth provider for authenticated requests
    private let authProvider = TokenAuthProvider()

    // Auth provider for the token-refresh demo (starts with an expired token)
    private let refreshAuthProvider = RefreshingAuthProvider()

    @State private var isHarborSetup = false

    func setupOnAppear() {
        Self.logger.log("setupOnAppear called", level: .info)
        Task {
            await setupHarbor()
            Self.logger.log("setupHarbor completed", level: .info)
        }
    }

    private func setupHarbor() async {
        guard !isHarborSetup else { return }
        isHarborSetup = true
        
        // Set default headers for all requests
        await Harbor.setDefaultHeaderParameters([
            "X-Client-Version": "1.0.0",
            "X-Client-Platform": "iOS"
        ])

        // Set default cache type
        await Harbor.setDefaultCacheType(.urlCache())

        // Enable debug logging
        await Harbor.setLoggingEnabled(true)

        // Configure JRpc
        await HarborJRPC.setURL(URL(string: "https://ethereum.publicnode.com")!)

        // Configure mTLS (optional - requires certificate)
        // guard let url = Bundle.main.url(forResource: "certificate", withExtension: "p12") else { return }
        // let mTLS = HMTLS(p12FileUrl: url) { "notapassword" }
        // try await Harbor.setMTLS(mTLS)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - Basic Requests Section
                        Section {
                            SectionHeader(title: "Basic GET Requests")

                            ExampleButton(title: "GET - Simple Request", icon: "arrow.down.circle", action: { performBasicGet() })
                            

                            ExampleButton(title: "GET - With Path Parameter", icon: "arrow.right.circle", action: { performGetWithPathParameter() })
                            

                            ExampleButton(title: "GET - With Query Params", icon: "magnifyingglass", action: { performGetWithQueryParams() })
                            
                        }

                        // MARK: - POST Requests
                        Section {
                            SectionHeader(title: "POST Requests")

                            ExampleButton(title: "POST - Create Resource", icon: "plus.circle", action: { performPostRequest() })

                            ExampleButton(title: "POST - Multipart Upload", icon: "paperclip", action: { performMultipartPost() })
                        }

                        // MARK: - PUT & PATCH
                        Section {
                            SectionHeader(title: "PUT & PATCH")

                            ExampleButton(title: "PUT - Full Update", icon: "arrow.triangle.2.circlepath", action: { performPutRequest() })

                            ExampleButton(title: "PATCH - Partial Update", icon: "pencil", action: { performPatchRequest() })
                        }

                        // MARK: - DELETE
                        Section {
                            SectionHeader(title: "DELETE")

                            ExampleButton(title: "DELETE - Remove Resource", icon: "trash", action: { performDeleteRequest() })
                        }

                        // MARK: - Caching
                        Section {
                            SectionHeader(title: "Caching")

                            ExampleButton(title: "GET - With Custom Cache", icon: "externaldrive", action: { performCachedRequest() })

                            ExampleButton(title: "GET - With URLCache (ETags)", icon: "network", action: { performURLCacheRequest() })

                            ExampleButton(title: "GET - Cache Only", icon: "internaldrive", action: { performCacheOnlyRequest() })

                            ExampleButton(title: "GET - Remote Only", icon: "antenna.radiowaves.left.and.right", action: { performRemoteOnlyRequest() })

                            ExampleButton(title: "Clear All Cache", icon: "xmark.circle", isDestructive: true, action: { clearAllCache() })
                        }

                        // MARK: - Streaming
                        Section {
                            SectionHeader(title: "Streaming")

                            ExampleButton(title: "Stream - Cache + Remote", icon: "arrow.triangle.2.circlepath.circle", action: { performStreamRequest() })

                            ExampleButton(title: "Stream - Cache Only", icon: "internaldrive", action: { performStreamCacheOnlyRequest() })

                            ExampleButton(title: "Stream - Remote Only", icon: "antenna.radiowaves.left.and.right", action: { performStreamRemoteOnlyRequest() })
                        }

                        // MARK: - Pagination
                        Section {
                            SectionHeader(title: "Pagination")

                            ExampleButton(title: "GET - Paginated", icon: "number", action: { performPaginatedRequest() })
                        }

                        // MARK: - Authentication
                        Section {
                            SectionHeader(title: "Authentication")

                            ExampleButton(title: "GET - With Auth", icon: "lock.shield", action: { performAuthenticatedRequest() })

                            ExampleButton(title: "GET - Auth with Token Refresh", icon: "lock.rotation", action: { performAuthWithRefresh() })
                        }

                        // MARK: - Headers
                        Section {
                            SectionHeader(title: "Custom Headers")

                            ExampleButton(title: "GET - Custom Headers", icon: "header", action: { performRequestWithHeaders() })
                        }

                        // MARK: - Retry
                        Section {
                            SectionHeader(title: "Retry Logic")

                            ExampleButton(title: "GET - With Retry (3x)", icon: "arrow.clockwise.circle", action: { performRequestWithRetry() })
                        }

                        // MARK: - Error Handling
                        Section {
                            SectionHeader(title: "Error Handling")

                            ExampleButton(title: "Handle Errors", icon: "exclamationmark.triangle", action: { performErrorHandling() })
                        }

                        // MARK: - JSON-RPC
                        Section {
                            SectionHeader(title: "JSON-RPC (Ethereum)")

                            ExampleButton(title: "JRPC - Block Number", icon: "bitcoinsign.circle", action: { performJRPCRequest() })

                            ExampleButton(title: "JRPC - Get Balance", icon: "dollarsign.circle", action: { performJRPCBalanceRequest() })
                        }

                        // MARK: - mTLS
                        Section {
                            SectionHeader(title: "Security (mTLS)")

                            ExampleButton(title: "GET - With mTLS", icon: "lock.icloud", action: { performMTLSRequest() })

                            ExampleButton(title: "Configure SSL Pinning", icon: "checkmark.shield", action: { configureSSLPinning() })
                        }

                        // MARK: - Mocking
                        Section {
                            SectionHeader(title: "Mocking")
                            Toggle(isOn: Binding(
                                get: { Harbor.mocksEnabled },
                                set: { Harbor.setMocksEnabled($0) }
                            )) {
                                HStack {
                                    Image(systemName: "theatermasks")
                                        .frame(width: 24)
                                    Text("Enable Mocks")
                                }
                            }
                            .padding()
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(10)

                            ExampleButton(title: "Register Mock Response", icon: "text.badge.plus", action: { registerMock() })
                            ExampleButton(title: "Clear Mocks", icon: "trash", isDestructive: true, action: {
                                Harbor.removeAllMocks()
                                addResult("All mocks removed")
                            })
                        }

                        // MARK: - Debug
                        Section {
                            SectionHeader(title: "Debug Mode")

                            ExampleButton(title: "GET - Debug Mode", icon: "antenna.radiowaves.left.and.right", action: { performDebugRequest() })
                        }

                        Spacer(minLength: 40)
                    }
                    .padding()
                }

                // MARK: - Sticky Results Console
                ResultsConsoleView(results: results) {
                    results.removeAll()
                }
            }
            .onAppear {
                setupOnAppear()
            }
            .navigationTitle("Harbor Examples")
            .navigationBarItems(trailing:
                Button(action: { isSettingsPresented = true }) {
                    Image(systemName: "gear")
                }
            )
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }

    // MARK: - Basic GET

    func performBasicGet() {
        Self.logger.log("performBasicGet called", level: .info)
        addResult("=== GET - Basic Request ===")
        performWithLoading {
            let response = await GetUsersRequest().request()
            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Success! Got \(users.count) users")
                    if let first = users.first {
                        addResult("First user: \(first.name) (\(first.email))")
                    }
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performGetWithPathParameter() {
        addResult("=== GET - Path Parameter ===")
        performWithLoading {
            let response = await GetUserRequest(userId: 1).request()
            await MainActor.run {
                switch response {
                case .success(let user):
                    addResult("User: \(user.name)")
                    addResult("Email: \(user.email)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performGetWithQueryParams() {
        addResult("=== GET - Query Parameters ===")
        performWithLoading {
            let response = await SearchUsersRequest(query: "Bret").request()
            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Found \(users.count) users")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - POST

    func performPostRequest() {
        addResult("=== POST - Create Resource ===")
        performWithLoading {
            let response = await CreatePostRequest(
                title: "My New Post",
                body: "This is the body of my post",
                userId: 1
            ).request()

            await MainActor.run {
                switch response {
                case .success:
                    addResult("Post created successfully!")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performMultipartPost() {
        addResult("=== POST - Multipart ===")
        performWithLoading {
            let imageData = "fake image data".data(using: .utf8)
            let response = await UploadPostRequest(
                title: "Post with Image",
                body: "Description",
                userId: 1,
                imageData: imageData
            ).request()

            await MainActor.run {
                switch response {
                case .success:
                    addResult("Upload successful!")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - PUT & PATCH

    func performPutRequest() {
        addResult("=== PUT - Full Update ===")
        performWithLoading {
            let response = await UpdatePostRequest(
                postId: 1,
                title: "Updated Title",
                body: "Updated body content",
                userId: 1
            ).request()

            await MainActor.run {
                switch response {
                case .success:
                    addResult("Post updated successfully!")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performPatchRequest() {
        addResult("=== PATCH - Partial Update ===")
        performWithLoading {
            let response = await PatchPostRequest(
                postId: 1,
                title: "Just the Title"
            ).request()

            await MainActor.run {
                switch response {
                case .success:
                    addResult("Post patched successfully!")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - DELETE

    func performDeleteRequest() {
        addResult("=== DELETE - Remove Resource ===")
        performWithLoading {
            let response = await DeletePostRequest(postId: 1).request()

            await MainActor.run {
                switch response {
                case .success:
                    addResult("Post deleted successfully!")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Caching

    func performCachedRequest() {
        addResult("=== GET - Custom Cache ===")
        performWithLoading {
            let response = await GetUserProfileRequest(userId: 1).request()

            await MainActor.run {
                switch response {
                case .success(let user):
                    addResult("Cached user: \(user.name)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performURLCacheRequest() {
        addResult("=== GET - URLCache ===")
        performWithLoading {
            let response = await GetPostsRequest().request()

            await MainActor.run {
                switch response {
                case .success(let posts):
                    addResult("Got \(posts.count) posts (with ETag support)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performCacheOnlyRequest() {
        addResult("=== GET - Cache Only ===")
        performWithLoading {
            // First, populate cache
            _ = await GetUserRequest(userId: 1).request()

            // Now try cache only
            let cachedUser = await GetUserRequest(userId: 1).cache()
            await MainActor.run {
                if let user = cachedUser {
                    addResult("Cache hit! User: \(user.name)")
                } else {
                    addResult("No cached data found")
                }
            }
        }
    }

    func performRemoteOnlyRequest() {
        addResult("=== GET - Remote Only ===")
        performWithLoading {
            let response = await RemoteOnlyUsersRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Got \(users.count) users (bypassed cache)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func clearAllCache() {
        addResult("=== Clearing Cache ===")
        performWithLoading {
            await Harbor.clearAllCache()
            await MainActor.run {
                addResult("All cache cleared!")
            }
        }
    }

    // MARK: - Streaming

    func performStreamRequest() {
        addResult("=== Stream - Cache + Remote ===")
        performWithLoading {
            do {
                // First populate cache
                _ = await GetUserRequest(userId: 1).request()

                // Now stream
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .cacheAndRemote) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        addResult("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    addResult("Stream error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performStreamCacheOnlyRequest() {
        addResult("=== Stream - Cache Only ===")
        performWithLoading {
            do {
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .cacheOnly) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        addResult("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    if case HRequestError.noCachedDataFound = error {
                        addResult("Error: \(error.localizedDescription) (run \"Stream - Cache + Remote\" first to populate the cache)")
                    } else {
                        addResult("Stream error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func performStreamRemoteOnlyRequest() {
        addResult("=== Stream - Remote Only ===")
        performWithLoading {
            do {
                for try await (user, origin) in GetUserRequest(userId: 1).requestStream(source: .remoteOnly) {
                    let source = origin == .cache ? "CACHE" : "REMOTE"
                    await MainActor.run {
                        addResult("[\(source)] User: \(user.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    addResult("Stream error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Pagination

    func performPaginatedRequest() {
        addResult("=== GET - Paginated ===")
        performWithLoading {
            let response = await GetPaginatedPostsRequest(page: 1, limit: 5).request()

            await MainActor.run {
                switch response {
                case .success(let posts):
                    addResult("Got \(posts.count) posts (page 1)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Authentication

    func performAuthenticatedRequest() {
        addResult("=== GET - Authenticated ===")
        performWithLoading {
            // Set auth provider
            authProvider.setToken("demo_token_123", expiresIn: 3600)
            await Harbor.setAuthProvider(authProvider)

            let response = await GetPrivateDataRequest().request()

            await MainActor.run {
                switch response {
                case .success(let user):
                    addResult("Authenticated user: \(user.name)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performAuthWithRefresh() {
        addResult("=== Auth with Token Refresh ===")
        // Route auth-demo.local through the local stub server (no network needed).
        URLProtocol.registerClass(AuthDemoStubProtocol.self)
        refreshAuthProvider.reset()
        performWithLoading {
            // The provider starts with an expired token that the stub server rejects
            // with a 401; it then refreshes the token and Harbor retries automatically.
            await Harbor.setAuthProvider(refreshAuthProvider)

            let response = await GetSecureDemoDataRequest().request()

            await MainActor.run {
                switch response {
                case .success(let data):
                    addResult("Server rejected the expired token with 401")
                    addResult("Provider refreshed the token; Harbor retried automatically")
                    addResult("Retry succeeded: \(data.message)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Headers

    func performRequestWithHeaders() {
        addResult("=== GET - Custom Headers ===")
        performWithLoading {
            let response = await GetDataWithHeadersRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Got \(users.count) users (with custom headers)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Retry

    func performRequestWithRetry() {
        addResult("=== GET - With Retry ===")
        performWithLoading {
            let response = await GetUnreliableDataRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Got \(users.count) users (after retries)")
                case .error(let error):
                    addResult("Error after retries: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Error Handling

    func performErrorHandling() {
        addResult("=== Error Handling Examples ===")
        performWithLoading {
            let response = await ErrorProneRequest().request()

            await MainActor.run {
                switch response {
                case .success(let errorResponse):
                    addResult("Error response: \(errorResponse.error)")
                case .error(let error):
                    addResult("Parsed error: \(error)")
                    addResult("Error type: \(type(of: error))")
                }
            }
        }
    }

    // MARK: - JSON-RPC

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
            let request = GetBalanceRequest(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb")
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

    // MARK: - Security

    func performMTLSRequest() {
        addResult("=== mTLS Request ===")
        performWithLoading {
            // Load the client certificate bundled with the app and configure mTLS.
            guard let p12URL = Bundle.main.url(forResource: "certificate", withExtension: "p12") else {
                await MainActor.run {
                    addResult("certificate.p12 not found in the app bundle")
                }
                return
            }

            do {
                let mTLS = HMTLS(p12FileUrl: p12URL) { "notapassword" }
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
                    addResult("Could not configure mTLS: \(message)")
                }
                return
            }

            await MainActor.run {
                addResult("Client identity loaded from certificate.p12")
            }

            let response = await MTLSRequest().request()

            await MainActor.run {
                switch response {
                case .success(let result):
                    addResult("MTLS Success: \(result.user ?? "N/A")")
                case .error(let error):
                    addResult("MTLS Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func configureSSLPinning() {
        addResult("=== Configuring SSL Pinning ===")
        Task {
            let host = "jsonplaceholder.typicode.com"
            do {
                // Read the live server certificate and compute its pin.
                let certificate = try await ServerCertificateFetcher.fetchCertificate(from: host)
                guard let pin = await Harbor.computePin(for: certificate) else {
                    await MainActor.run {
                        addResult("Could not compute a pin for the server certificate")
                    }
                    return
                }
                await MainActor.run {
                    addResult("Computed pin: \(pin)")
                }

                // Pin only the demo host; other endpoints keep default validation.
                await Harbor.setSSLPinningKeys([pin], forHosts: [host])

                // Verify that a pinned request to the host succeeds.
                let response = await GetUsersRequest().request()
                await MainActor.run {
                    switch response {
                    case .success(let users):
                        addResult("Pinned request to \(host) succeeded (\(users.count) users)")
                    case .error(let error):
                        addResult("Pinned request failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                await MainActor.run {
                    addResult("Could not fetch the server certificate: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Mocking

    func registerMock() {
        let json = """
        [
          {
            "id": 999,
            "name": "Mocked User",
            "email": "mock@example.com"
          }
        ]
        """
        let mock = HMock(request: GetUsersRequest.self, statusCode: 200, jsonResponse: json)
        Harbor.register(mock: mock)
        addResult("Registered mock for GetUsersRequest. Toggle 'Enable Mocks' and fetch users to see it.")
    }

    // MARK: - Debug

    func performDebugRequest() {
        addResult("=== Debug Request ===")
        performWithLoading {
            await Harbor.setLoggingEnabled(true)
            let response = await DebugGetUsersRequest().request()

            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Debug: Got \(users.count) users")
                case .error(let error):
                    addResult("Debug Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Runs an async operation toggling the loading overlay.
    private func performWithLoading(_ operation: @escaping () async -> Void) {
        isLoading = true
        Task {
            await operation()
            await MainActor.run { isLoading = false }
        }
    }

    func addResult(_ text: String) {
        results.append(text)
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 10)
    }
}

struct ExampleButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    var action: (() -> Void)?

    var body: some View {
        if let action = action {
            Button(action: {
                action()
            }) {
                buttonContent
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            buttonContent
        }
    }

    private var buttonContent: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(isDestructive ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
        .foregroundColor(isDestructive ? .red : .accentColor)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor, lineWidth: isDestructive ? 0 : 1)
        )
    }
}

/// Simple read-only summary of the Harbor configuration used by the example.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Network")) {
                    Label("Cache: URLCache (default)", systemImage: "externaldrive")
                    Label("Timeout: 15s (default)", systemImage: "clock")
                    Label("JRPC: ethereum.publicnode.com", systemImage: "link")
                }

                Section(header: Text("Default Headers")) {
                    Label("X-Client-Version: 1.0.0", systemImage: "list.bullet.rectangle")
                    Label("X-Client-Platform: iOS", systemImage: "list.bullet.rectangle")
                }

                Section(header: Text("Debug")) {
                    Label("Logging: Enabled", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}

/// Console-style output panel pinned to the bottom of the screen.
/// Shows example outputs and auto-scrolls to the newest entry.
struct ResultsConsoleView: View {
    let results: [String]
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                Text("Output")
                    .font(.headline)
                Spacer()
                if !results.isEmpty {
                    Button("Clear", action: onClear)
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if results.isEmpty {
                            Text("Tap an example to see its output here")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                                Text(result)
                                    .id(index)
                            }
                        }
                    }
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .onChange(of: results.count) { _ in
                    if let lastIndex = results.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 160)
            .background(Color.gray.opacity(0.1))
        }
    }
}

#Preview {
    RequestsView()
}
