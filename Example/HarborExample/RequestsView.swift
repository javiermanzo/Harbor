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
    @State private var authProvider = TokenAuthProvider()

    // Auth provider for the token-refresh demo (starts with an expired token)
    @State private var refreshAuthProvider = RefreshingAuthProvider()

    private static var isHarborSetup = false
    @State private var isMocksEnabled: Bool = false

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
            .navigationTitle("Harbor Examples")
            .navigationBarItems(trailing:
                Button(action: { isSettingsPresented = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .semibold))
                }
            )
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
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
            let cachedUser = await GetUserRequest(userId: 1).cache()
            await MainActor.run {
                if let user = cachedUser {
                    addResult("Successfully read from cache: \(user.name)")
                } else {
                    addResult("Cache miss (run a standard GET first to populate it)")
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
            // Inject the stub protocol into an ephemeral session so it intercepts requests to the demo host.
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [AuthDemoStubProtocol.self] + (config.protocolClasses ?? [])
            await Harbor.setCustomURLSession(URLSession(configuration: config))
            
            // The provider starts with an expired token that the stub server rejects
            // with a 401; it then refreshes the token and Harbor retries automatically.
            await Harbor.setAuthProvider(refreshAuthProvider)

            let response = await GetSecureDemoDataRequest().request()
            
            // Restore default Harbor session
            await Harbor.setCustomURLSession(nil)

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
                    addResult("mTLS successful!")
                    addResult("Secure connection established with client certificate.")
                    addResult("Identity: \(result.sslClientSDN ?? "Unknown")")
                case .error(let error):
                    if case .timeout = error {
                        addResult("Request timed out.")
                        addResult("Note: The public test server is frequently offline.")
                        addResult("However, your client certificate was loaded and Harbor is configured correctly.")
                    } else {
                        addResult("MTLS Error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func configureSSLPinning() {
        addResult("=== Configuring SSL Pinning ===")
        performWithLoading {
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
        Task {
            await Harbor.register(mock: mock)
            await MainActor.run {
                addResult("Registered mock for GetUsersRequest. Toggle 'Enable Mocks' and fetch users to see it.")
            }
        }
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
    private func performWithLoading(_ operation: @escaping @Sendable () async -> Void) {
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

struct ExampleSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                content
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

struct ExampleButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 32)
                    .foregroundColor(isDestructive ? .red : .accentColor)
                
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color.gray.opacity(0.5))
            }
            .padding()
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDestructive ? Color.red.opacity(0.3) : Color.accentColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(SpringyButtonStyle())
    }
}

struct SpringyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Interactive configuration panel for Harbor settings.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var timeoutInterval: Double = 15.0
    @State private var mocksEnabled: Bool = false
    @State private var isLoggingEnabled: Bool = true
    @State private var cacheTypeIndex: Int = 0 // 0: urlCache, 1: disabled

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Network")) {
                    Stepper("Timeout: \(Int(timeoutInterval))s", value: $timeoutInterval, in: 5...60)
                        .onChange(of: timeoutInterval) { newValue in
                            Task { await Harbor.setDefaultTimeoutInterval(newValue) }
                        }
                    
                    Picker("Cache Type", selection: $cacheTypeIndex) {
                        Text(".urlCache").tag(0)
                        Text(".disabled").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: cacheTypeIndex) { newValue in
                        Task {
                            let cacheType: HCache.CacheType = newValue == 0 ? .urlCache() : .disabled
                            await Harbor.setDefaultCacheType(cacheType)
                        }
                    }
                }

                Section(header: Text("Debug")) {
                    Toggle("Enable Mocks", isOn: $mocksEnabled)
                        .onChange(of: mocksEnabled) { newValue in
                            Task { await Harbor.setMocksEnabled(newValue) }
                        }
                    
                    Toggle("Enable Logging", isOn: $isLoggingEnabled)
                        .onChange(of: isLoggingEnabled) { newValue in
                            Task { await Harbor.setLoggingEnabled(newValue) }
                        }
                }
            }
            .navigationTitle("Global Settings")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .onAppear {
                Task {
                    let currentMocks = await Harbor.mocksEnabled
                    await MainActor.run {
                        self.mocksEnabled = currentMocks
                        // Timeout and Logging state are not currently exposed as getters by Harbor, 
                        // so we display the defaults (or last set values).
                    }
                }
            }
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
            HStack {
                Text("Terminal Output")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                if !results.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if results.isEmpty {
                            Text("> Ready")
                                .foregroundColor(.green)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(">")
                                        .foregroundColor(.green)
                                    Text(result)
                                        .foregroundColor(.white)
                                }
                                .id(index)
                            }
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .onChange(of: results.count) { _ in
                    if let lastIndex = results.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 180)
            .background(Color(white: 0.1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: -5)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

#Preview {
    RequestsView()
}
