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

    // Values shown in the settings sheet (Harbor's defaults, or what the sheet applied last).
    @State private var timeoutInterval: Double = 15
    @State private var isLoggingEnabled: Bool = true
    @State private var cacheTypeIndex: Int = 0

    // Static logger using LogBird
    private static let logger = LogBird(subsystem: "com.harbor.example", category: "RequestsView")

    // Auth providers are actors (not `ObservableObject`s), so `@State` keeps one instance alive
    // across SwiftUI render passes.
    // Auth provider for authenticated requests
    @State private var authProvider = TokenAuthProvider()

    // Auth provider for the token-refresh demo (starts with an expired token)
    @State private var refreshAuthProvider = RefreshingAuthProvider()

    // Survives view re-creation; `RequestsView` is `@MainActor` (SwiftUI `View`), so the
    // flag is isolated to the main actor as well.
    @MainActor private static var isHarborSetup = false
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
            let response = await SearchUsersRequest(username: "Bret").request()
            await MainActor.run {
                switch response {
                case .success(let users):
                    addResult("Found \(users.count) user(s) with username Bret")
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
            // The type annotation selects the model-returning `request()` overload.
            let response: HResponseWithResult<Post> = await CreatePostRequest(
                title: "My New Post",
                body: "This is the body of my post",
                userId: 1
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    addResult("Post created successfully! Server assigned id \(post.id)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performRawBodyPost() {
        addResult("=== POST - Encodable rawBody ===")
        performWithLoading {
            // `rawBody` sends the pre-encoded model as-is with `Content-Type: application/json`.
            let post = Post(id: 0, userId: 1, title: "Encoded with JSONEncoder", body: "Sent through rawBody")
            let response: HResponseWithResult<Post> = await CreatePostWithModelRequest(post: post).request()

            await MainActor.run {
                switch response {
                case .success(let created):
                    addResult("Post created from an Encodable model! Server assigned id \(created.id)")
                    addResult("Title echoed by the server: \(created.title)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performMultipartPost() {
        addResult("=== POST - Multipart ===")
        performWithLoading {
            // Write a placeholder file: multipart file parts are read (streamed) from disk.
            let imageFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("harbor-example-image.png")
            let imageWritten = (try? Data("fake image data".utf8).write(to: imageFileURL)) != nil
            let response = await UploadPostRequest(
                title: "Post with Image",
                body: "Description",
                userId: 1,
                imageFileURL: imageWritten ? imageFileURL : nil
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
            let response: HResponseWithResult<Post> = await UpdatePostRequest(
                postId: 1,
                title: "Updated Title",
                body: "Updated body content",
                userId: 1
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    addResult("Post updated successfully! New title: \(post.title)")
                case .error(let error):
                    addResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    func performPatchRequest() {
        addResult("=== PATCH - Partial Update ===")
        performWithLoading {
            let response: HResponseWithResult<Post> = await PatchPostRequest(
                postId: 1,
                title: "Just the Title"
            ).request()

            await MainActor.run {
                switch response {
                case .success(let post):
                    addResult("Post patched successfully! Title: \(post.title) (body kept: \(post.body.count) chars)")
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
            // Reads the entry of "GET - With Custom Cache" without touching the network.
            let request = GetUserProfileRequest(userId: 1)
            let cachedUser = await request.cache()
            let eTag = await request.cachedETag()
            await MainActor.run {
                if let user = cachedUser {
                    addResult("Successfully read from cache: \(user.name)")
                    addResult("Cached ETag: \(eTag ?? "none")")
                } else {
                    addResult("Cache miss (run \"GET - With Custom Cache\" first to populate it)")
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
        // Read the @State provider on the main actor before handing it to the task.
        let authProvider = authProvider
        performWithLoading {
            await authProvider.setToken("demo_token_123", expiresIn: 3600)
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
        // Read the @State provider on the main actor before handing it to the task.
        let refreshAuthProvider = refreshAuthProvider
        performWithLoading {
            await refreshAuthProvider.reset()

            // Route auth-demo.local through the local stub server (no real network traffic): the
            // session's `protocolClasses` inject the stub, so no global registration is required.
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [AuthDemoStubProtocol.self] + (config.protocolClasses ?? [])
            // A custom session is used as-is: Harbor's delegate keeps SSL pinning, mTLS and the
            // cross-origin redirect policy active on it.
            let delegate = await Harbor.makeURLSessionDelegate()
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            await Harbor.setCustomURLSession(session)

            // The provider starts with an expired token that the stub server rejects with a 401.
            // Harbor calls `authFailed()` once, the provider refreshes the token, and Harbor
            // re-sends the request with the new header.
            await Harbor.setAuthProvider(refreshAuthProvider)

            let response = await GetSecureDemoDataRequest().request()
            let refreshCount = await refreshAuthProvider.refreshCount

            // Restore the default Harbor sessions and release the demo session
            await Harbor.setCustomURLSession(nil)
            session.finishTasksAndInvalidate()

            await MainActor.run {
                switch response {
                case .success(let data):
                    addResult("Server rejected the expired token with 401")
                    addResult("authFailed() refreshed the token \(refreshCount)x; Harbor re-sent the request")
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
                // Scope the client identity to the mTLS test host so it is never offered elsewhere.
                let mTLS = HMTLS(p12FileUrl: p12URL, hosts: ["certauth.cryptomix.com"]) { "notapassword" }
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
                let response = await GetPinnedUsersRequest().request()
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
        let mock = HMock(request: GetUsersRequest.self, statusCode: 200, jsonResponse: json, delay: 1.0)
        Task {
            await Harbor.register(mock: mock)
            await MainActor.run {
                addResult("Registered mock for GetUsersRequest. With 'Enable Mocks' on, run 'GET - Simple Request' to get the mocked user.")
            }
        }
    }

    // MARK: - Debug

    func performDebugRequest() {
        addResult("=== Debug Request ===")
        performWithLoading {
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

#Preview {
    RequestsView()
}
