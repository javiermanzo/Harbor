//
//  HarborRealServiceTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
@testable import Harbor

final class HarborRealServiceTests: XCTestCase {

    struct TestResource: HModel {
        let name: String
        let id: Int
    }

    struct GetTestResourceCustomCache: HGetRequestProtocol {
        typealias Model = TestResource
        let url = "https://pokeapi.co/api/v2/pokemon/ditto"
        let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: 60))
    }

    struct GetTestResourceURLCache: HGetRequestProtocol {
        typealias Model = TestResource
        let url = "https://pokeapi.co/api/v2/pokemon/mew"
        let queryParameters: [String: String]? = nil
        let cacheType: HCache.CacheType? = .urlCache()
    }

    struct GetTestResourceETag: HGetRequestProtocol {
        typealias Model = TestResource
        let url = "https://pokeapi.co/api/v2/pokemon/ditto"
        let cacheType: HCache.CacheType?

        init(urlCache: URLCache) {
            self.cacheType = .urlCache(urlCache: urlCache, requestCachePolicy: .useProtocolCachePolicy)
        }
    }

    /// Request con custom cache de larga duración para pruebas de ETag.
    struct GetTestResourceCustomCacheETag: HGetRequestProtocol {
        typealias Model = TestResource
        let url = "https://pokeapi.co/api/v2/pokemon/ditto"
        // Expiration larga para que no expire durante el test
        let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: 3600))
    }

    override func setUp() async throws {
        URLCache.shared.removeAllCachedResponses()
        LocalStubURLProtocol.clearStubs()

        let url = URL(string: "https://pokeapi.co/api/v2/pokemon/ditto")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"mocked-etag\""])!
        let data = "{\"name\": \"ditto\", \"id\": 132}".data(using: .utf8)!
        LocalStubURLProtocol.registerStub(for: url, data: data, response: response)

        let url2 = URL(string: "https://pokeapi.co/api/v2/pokemon/mew")!
        let response2 = HTTPURLResponse(url: url2, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "\"mocked-etag-mew\""])!
        LocalStubURLProtocol.registerStub(for: url2, data: data, response: response2)

        await Harbor.setProtocolClasses([LocalStubURLProtocol.self])
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
        await Harbor.setMocksOnlyInDebug(false)
        await Harbor.setDefaultCacheType(.disabled)
    }

    override func tearDown() async throws {
        URLCache.shared.removeAllCachedResponses()
        await Harbor.setProtocolClasses(nil)
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
    }

    func testRealNetworkConnection() async throws {
        try NetworkTestFlag.skipUnlessEnabled()
        await Harbor.setProtocolClasses(nil)
        let request = GetTestResourceCustomCache()
        let response = await request.request()
        switch response {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }
    }

    func testCustomCacheWithRealService() async throws {
        let request = GetTestResourceCustomCache()

        let initialCache = await request.cache()
        XCTAssertNil(initialCache)

        let response = await request.request()
        switch response {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }

        // Fetch from cache
        let cachedUser = await request.cache()
        XCTAssertNotNil(cachedUser)
        if cachedUser?.name == "ditto" || cachedUser?.name == "mew" {} else { XCTFail("Unexpected cached user name") }; XCTAssertTrue(cachedUser?.name == "ditto" || cachedUser?.name == "mew")
    }

    func testURLCacheWithRealService() async throws {
        let request = GetTestResourceURLCache()

        let initialCache = await request.cache()
        XCTAssertNil(initialCache)

        let response = await request.request()
        switch response {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }

        await waitForCachedResponse(of: request, in: .shared)

        let cachedUser = await request.cache()
        XCTAssertNotNil(cachedUser)
        if cachedUser?.name == "ditto" || cachedUser?.name == "mew" {} else { XCTFail("Unexpected cached user name") }; XCTAssertTrue(cachedUser?.name == "ditto" || cachedUser?.name == "mew")
    }

    func testCustomCacheRequestStream() async throws {
        let request = GetTestResourceCustomCache()

        // Populate cache
        let _ = await request.request()

        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .cacheAndRemote) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }

        XCTAssertEqual(resultsCount, 2, "Stream should return twice (once from cache, once from remote)")
    }

    func testURLCacheRequestStream() async throws {
        let request = GetTestResourceURLCache()

        // Populate cache
        let _ = await request.request()

        await waitForCachedResponse(of: request, in: .shared)

        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .cacheAndRemote) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }

        XCTAssertEqual(resultsCount, 2, "Stream should return twice (once from cache, once from remote)")
    }

    func testCustomCacheRequestStreamCacheOnly() async throws {
        let request = GetTestResourceCustomCache()

        let _ = await request.request()

        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .cacheOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                XCTAssertEqual(origin, .cache)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from cache")
    }

    func testCustomCacheRequestStreamRemoteOnly() async throws {
        let request = GetTestResourceCustomCache()

        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .remoteOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                XCTAssertEqual(origin, .remote)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from remote")
    }

    func testURLCacheRequestStreamCacheOnly() async throws {
        let request = GetTestResourceURLCache()

        // Populate cache
        let _ = await request.request()

        await waitForCachedResponse(of: request, in: .shared)

        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .cacheOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                XCTAssertEqual(origin, .cache)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from cache")
    }

    func testURLCacheRequestStreamRemoteOnly() async throws {
        let request = GetTestResourceURLCache()

        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .remoteOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                XCTAssertEqual(origin, .remote)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from remote")
    }

    // MARK: - ETag / 304 Not Modified Tests

    /// 1. Verifica que la GitHub API devuelve un header ETag en la primera respuesta.
    func testETagHeaderIsReceivedFromRealService() async throws {
        let url = URL(string: "https://pokeapi.co/api/v2/pokemon/ditto")!
        var urlRequest = URLRequest(url: url)
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(httpResponse.statusCode, 200)

        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
            ?? httpResponse.value(forHTTPHeaderField: "Etag")
            ?? httpResponse.value(forHTTPHeaderField: "etag")
        XCTAssertNotNil(etag, "La GitHub API debe devolver un header ETag")
        XCTAssertFalse(etag?.isEmpty ?? true, "El ETag no debe estar vacío")
    }

    /// 2. Verifica que el servidor responde 304 Not Modified cuando se envía el ETag
    ///    recibido mediante el header If-None-Match.
    func testETag304NotModifiedWithRealService() async throws {
        let url = URL(string: "https://pokeapi.co/api/v2/pokemon/ditto")!

        // Primera request — obtener ETag
        var firstRequest = URLRequest(url: url)
        firstRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let (_, firstResponse) = try await URLSession.shared.data(for: firstRequest)
        let firstHTTP = try XCTUnwrap(firstResponse as? HTTPURLResponse)
        XCTAssertEqual(firstHTTP.statusCode, 200)

        let etag = firstHTTP.value(forHTTPHeaderField: "ETag")
            ?? firstHTTP.value(forHTTPHeaderField: "Etag")
            ?? firstHTTP.value(forHTTPHeaderField: "etag")
        let unwrappedETag = try XCTUnwrap(etag, "La primera respuesta debe contener un ETag")

        // Segunda request — enviar If-None-Match con el ETag obtenido
        var secondRequest = URLRequest(url: url)
        secondRequest.cachePolicy = .reloadIgnoringLocalCacheData
        secondRequest.setValue(unwrappedETag, forHTTPHeaderField: "If-None-Match")

        let (secondData, secondResponse) = try await URLSession.shared.data(for: secondRequest)
        let secondHTTP = try XCTUnwrap(secondResponse as? HTTPURLResponse)

        // El servidor debe responder 304 Not Modified
        XCTAssertEqual(secondHTTP.statusCode, 304, "El servidor debe responder 304 cuando el ETag no cambió")
        XCTAssertTrue(secondData.isEmpty, "Un 304 no debe tener body")
    }

    /// 3. Verifica que Harbor, usando URLCache con .useProtocolCachePolicy, maneja el 304
    ///    de forma transparente: la segunda request debe devolver datos correctamente.
    func testETagCacheHitWithRealService() async throws {
        let urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        let request = GetTestResourceETag(urlCache: urlCache)

        // Primera request — llena el cache con la respuesta y el ETag
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("First request failed: \(err)")
        }

        await waitForCachedResponse(of: request, in: urlCache)

        // Segunda request — URLSession envía If-None-Match automáticamente.
        // El servidor responde 304 y URLCache devuelve el cuerpo cacheado de forma transparente.
        let secondResponse = await request.request()
        switch secondResponse {
        case .success(let user):
            XCTAssertEqual(user.name, "ditto", "La segunda request (304 manejado por URLCache) debe devolver los mismos datos")
        case .error(let err):
            XCTFail("Second request (expected transparent 304 cache hit) failed: \(err)")
        }
    }

    /// 4. Verifica que requestStream funciona correctamente con URLCache y ETag.
    func testETagURLCacheRequestStream() async throws {
        let urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        let request = GetTestResourceETag(urlCache: urlCache)

        // Primera request — llena el cache
        let _ = await request.request()
        await waitForCachedResponse(of: request, in: urlCache)

        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .remoteOnly) {
                if response.name == "ditto" || response.name == "mew" {} else { XCTFail("Unexpected name") }; XCTAssertTrue(response.name == "ditto" || response.name == "mew")
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }

        XCTAssertEqual(resultsCount, 1, "remoteOnly stream debe devolver exactamente un resultado")
    }

    // MARK: - ETag with Custom Cache Tests

    /// Verifica que Harbor guarda el ETag de la respuesta cuando se usa custom cache.
    func testCustomCacheStoresETag() async throws {
        let request = GetTestResourceCustomCacheETag()

        let response = await request.request()
        switch response {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }

        // El ETag debe haberse guardado en el custom cache
        let storedETag = await request.cachedETag()
        XCTAssertNotNil(storedETag, "El custom cache debe guardar el ETag recibido del servidor")
        XCTAssertFalse(storedETag?.isEmpty ?? true, "El ETag guardado no debe estar vacío")
    }

    /// Verifica que Harbor envía If-None-Match en la segunda request y maneja el 304 correctamente:
    /// el servidor responde 304 y Harbor devuelve los datos del custom cache de forma transparente.
    func testCustomCacheETag304HandledTransparently() async throws {
        let request = GetTestResourceCustomCacheETag()

        // Primera request — llena el cache y guarda el ETag
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let user):
            if user.name == "ditto" || user.name == "mew" {} else { XCTFail("Unexpected user name") }; XCTAssertTrue(user.name == "ditto" || user.name == "mew")
        case .error(let err):
            XCTFail("First request failed: \(err)")
        }

        // Verificar que el ETag fue guardado
        let storedETag = await request.cachedETag()
        XCTAssertNotNil(storedETag, "Debe haber un ETag guardado antes de la segunda request")

        // Segunda request — Harbor adjunta If-None-Match automáticamente.
        // El servidor responde 304 y Harbor retorna los datos del custom cache.
        let secondResponse = await request.request()
        switch secondResponse {
        case .success(let user):
            XCTAssertEqual(user.name, "ditto", "La segunda request (304 + custom cache) debe devolver los mismos datos")
        case .error(let err):
            XCTFail("Second request (expected 304 handled by custom cache) failed: \(err)")
        }
    }

    /// Waits until `urlCache` serves a cached response for `request`. URLCache persists
    /// responses asynchronously and exposes no completion barrier, so the wait polls
    /// `cachedResponse(for:)` until the entry is visible or `timeout` elapses.
    @discardableResult
    private func waitForCachedResponse<Request: HGetRequestProtocol>(of request: Request, in urlCache: URLCache, timeout: TimeInterval = 2) async -> Bool {
        guard let urlRequest = try? await HURLBuilder.buildUrlRequest(request: request) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if urlCache.cachedResponse(for: urlRequest) != nil { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return urlCache.cachedResponse(for: urlRequest) != nil
    }
}
