//
//  HarborExampleTests.swift
//  HarborExampleTests
//
//  Created by Javier Manzo on 21/02/2023.
//

import XCTest
import Harbor
@testable import HarborExample

/// Tests of the demo requests, models and auth providers. None of them reaches the real network:
/// requests are answered by Harbor mocks or by the demo's local stub server.
@MainActor
final class HarborExampleTests: XCTestCase {

    override func setUp() async throws {
        await Harbor.setMocksEnabled(true)
        await Harbor.removeAllMocks()
    }

    override func tearDown() async throws {
        await Harbor.removeAllMocks()
        await Harbor.setAuthProvider(nil)
        await Harbor.setCustomURLSession(nil)
    }

    // MARK: - Request definitions

    func testGetUserRequestFillsPathParameter() {
        let request = GetUserRequest(userId: 7)

        XCTAssertTrue(request.url.hasSuffix("/users/{id}"))
        XCTAssertEqual(request.pathParameters, ["id": "7"])
    }

    func testSearchUsersRequestFiltersByUsername() {
        XCTAssertEqual(SearchUsersRequest(username: "Bret").queryParameters, ["username": "Bret"])
    }

    func testUploadPostRequestBuildsMultipartBody() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/image.png")
        let request = UploadPostRequest(title: "Title", body: "Body", userId: 3, imageFileURL: fileURL)

        let multipart = try XCTUnwrap(request.multipartBody)
        guard case .text(let title)? = multipart["title"] else { return XCTFail("title must be a text part") }
        XCTAssertEqual(title, "Title")
        guard case .text(let userId)? = multipart["userId"] else { return XCTFail("userId must be a text part") }
        XCTAssertEqual(userId, "3")
        guard case .file(let url, let mimeType, let fileName)? = multipart["image"] else {
            return XCTFail("image must be a file part")
        }
        XCTAssertEqual(url, fileURL)
        XCTAssertEqual(mimeType, "image/png")
        XCTAssertEqual(fileName, "image.png")
    }

    func testUploadPostRequestWithoutImageHasNoFilePart() throws {
        let request = UploadPostRequest(title: "Title", body: "Body", userId: 3, imageFileURL: nil)

        let multipart = try XCTUnwrap(request.multipartBody)
        XCTAssertNil(multipart["image"])
        XCTAssertEqual(multipart.count, 3)
    }

    func testCreatePostWithModelRequestSendsEncodedModelAsRawBody() throws {
        let post = Post(id: 0, userId: 1, title: "Title", body: "Body")
        let request = CreatePostWithModelRequest(post: post)

        let rawBody = try XCTUnwrap(request.rawBody)
        let decoded = try JSONDecoder().decode(Post.self, from: rawBody)
        XCTAssertEqual(decoded.title, "Title")
        XCTAssertEqual(decoded.userId, 1)
        XCTAssertNil(request.bodyParameters)
    }

    // MARK: - Models

    func testMtlsModelDecodesServerKeys() throws {
        let json = #"{"SSL_CLIENT_S_DN": "CN=Harbor", "SSL_CLIENT_VERIFY": "SUCCESS"}"#
        let model = try JSONDecoder().decode(MtlsModel.self, from: Data(json.utf8))

        XCTAssertEqual(model.sslClientSDN, "CN=Harbor")
        XCTAssertEqual(model.sslClientVerify, "SUCCESS")
        XCTAssertNil(model.user)
    }

    // MARK: - Mocking

    func testMockedGetDecodesResponse() async {
        let json = #"[{"id": 999, "name": "Mocked User", "email": "mock@example.com"}]"#
        await Harbor.register(mock: HMock(request: GetUsersRequest.self, statusCode: 200, jsonResponse: json))

        let response = await GetUsersRequest().request()

        guard case .success(let users) = response else { return XCTFail("expected a mocked success, got \(response)") }
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.name, "Mocked User")
    }

    func testMockedPostDecodesCreatedPost() async {
        let json = #"{"id": 101, "userId": 1, "title": "My New Post", "body": "Body"}"#
        await Harbor.register(mock: HMock(request: CreatePostRequest.self, statusCode: 201, jsonResponse: json))

        let response: HResponseWithResult<Post> = await CreatePostRequest(title: "My New Post", body: "Body", userId: 1).request()

        guard case .success(let post) = response else { return XCTFail("expected a mocked success, got \(response)") }
        XCTAssertEqual(post.id, 101)
    }

    func testMockedErrorStatusIsReportedAsApiError() async {
        await Harbor.register(mock: HMock(request: GetUsersRequest.self, statusCode: 404, jsonResponse: "{}"))

        let response = await GetUsersRequest().request()

        guard case .error(let error) = response, case .api(let statusCode, _) = error else {
            return XCTFail("expected an .api error, got \(response)")
        }
        XCTAssertEqual(statusCode, 404)
    }

    // MARK: - Authentication

    func testRefreshingAuthProviderRefreshesTokenOnceAfterRejection() async {
        let provider = RefreshingAuthProvider()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthDemoStubProtocol.self] + (config.protocolClasses ?? [])
        let delegate = await Harbor.makeURLSessionDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        await Harbor.setCustomURLSession(session)
        await Harbor.setAuthProvider(provider)

        let response = await GetSecureDemoDataRequest().request()

        guard case .success(let data) = response else { return XCTFail("expected success after the refresh, got \(response)") }
        XCTAssertEqual(data.message, "Secure data unlocked")
        let refreshCount = await provider.refreshCount
        XCTAssertEqual(refreshCount, 1)
    }

    func testTokenAuthProviderReturnsHeaderOnlyForValidToken() async {
        let provider = TokenAuthProvider()
        let missing = await provider.getAuthorizationHeader()
        XCTAssertNil(missing)

        await provider.setToken("abc", expiresIn: 60)
        let valid = await provider.getAuthorizationHeader()
        XCTAssertEqual(valid?.key, "Authorization")
        XCTAssertEqual(valid?.value, "Bearer abc")

        await provider.setToken("abc", expiresIn: -1)
        let expired = await provider.getAuthorizationHeader()
        XCTAssertNil(expired)
    }
}
