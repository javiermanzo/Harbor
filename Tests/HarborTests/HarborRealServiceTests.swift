//
//  HarborRealServiceTests.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import XCTest
@testable import Harbor

final class HarborRealServiceTests: XCTestCase {
    
    struct GithubUser: HModel {
        let login: String
        let id: Int
    }
    
    struct GetGithubUserCustomCache: HGetRequestProtocol {
        typealias Model = GithubUser
        let url = "https://api.github.com/users/octocat"
        let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: 60))
    }
    
    struct GetGithubUserURLCache: HGetRequestProtocol {
        typealias Model = GithubUser
        let url = "https://api.github.com/users/octocat"
        let queryParameters: [String: String]? = ["v": UUID().uuidString]
        let cacheType: HCache.CacheType? = .urlCache()
    }

    struct GetGithubUserETag: HGetRequestProtocol {
        typealias Model = GithubUser
        let url = "https://api.github.com/users/octocat"
        let cacheType: HCache.CacheType?

        init(urlCache: URLCache) {
            self.cacheType = .urlCache(urlCache: urlCache, requestCachePolicy: .useProtocolCachePolicy)
        }
    }

    /// Request con custom cache de larga duración para pruebas de ETag.
    struct GetGithubUserCustomCacheETag: HGetRequestProtocol {
        typealias Model = GithubUser
        let url = "https://api.github.com/users/octocat"
        // Expiration larga para que no expire durante el test
        let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: 3600))
    }
    
    override func setUp() async throws {
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
        await Harbor.setMocksOnlyInDebug(false)
        await Harbor.setDefaultCacheType(.disabled)
    }

    override func tearDown() async throws {
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
    }
    
    func testCustomCacheWithRealService() async throws {
        let request = GetGithubUserCustomCache()
        
        let initialCache = await request.cache()
        XCTAssertNil(initialCache)
        
        let response = await request.request()
        switch response {
        case .success(let user):
            XCTAssertEqual(user.login, "octocat")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }
        
        // Fetch from cache
        let cachedUser = await request.cache()
        XCTAssertNotNil(cachedUser)
        XCTAssertEqual(cachedUser?.login, "octocat")
    }
    
    func testURLCacheWithRealService() async throws {
        let request = GetGithubUserURLCache()
        
        let initialCache = await request.cache()
        XCTAssertNil(initialCache)
        
        let response = await request.request()
        switch response {
        case .success(let user):
            XCTAssertEqual(user.login, "octocat")
        case .error(let err):
            XCTFail("Request failed: \(err)")
        }
        
        // URLCache might need a moment to write to disk if it does so asynchronously
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let cachedUser = await request.cache()
        XCTAssertNotNil(cachedUser)
        XCTAssertEqual(cachedUser?.login, "octocat")
    }
    
    func testCustomCacheRequestStream() async throws {
        let request = GetGithubUserCustomCache()
        
        // Populate cache
        let _ = await request.request()
        
        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .cacheAndRemote) {
                XCTAssertEqual(response.login, "octocat")
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        
        XCTAssertEqual(resultsCount, 2, "Stream should return twice (once from cache, once from remote)")
    }
    
    func testURLCacheRequestStream() async throws {
        let request = GetGithubUserURLCache()
        
        // Populate cache
        let _ = await request.request()
        
        // Give URLCache time to persist
        try await Task.sleep(nanoseconds: 500_000_000)
        
        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .cacheAndRemote) {
                XCTAssertEqual(response.login, "octocat")
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        
        XCTAssertEqual(resultsCount, 2, "Stream should return twice (once from cache, once from remote)")
    }
    
    func testCustomCacheRequestStreamCacheOnly() async throws {
        let request = GetGithubUserCustomCache()
        
        let _ = await request.request()
        
        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .cacheOnly) {
                XCTAssertEqual(response.login, "octocat")
                XCTAssertEqual(origin, .cache)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from cache")
    }

    func testCustomCacheRequestStreamRemoteOnly() async throws {
        let request = GetGithubUserCustomCache()
        
        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .remoteOnly) {
                XCTAssertEqual(response.login, "octocat")
                XCTAssertEqual(origin, .remote)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from remote")
    }

    func testURLCacheRequestStreamCacheOnly() async throws {
        let request = GetGithubUserURLCache()
        
        // Populate cache
        let _ = await request.request()
        
        // Give URLCache time to persist
        try await Task.sleep(nanoseconds: 500_000_000)
        
        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .cacheOnly) {
                XCTAssertEqual(response.login, "octocat")
                XCTAssertEqual(origin, .cache)
                resultsCount += 1
            }
        } catch {
            XCTFail("Stream failed: \(error)")
        }
        XCTAssertEqual(resultsCount, 1, "Stream should return once from cache")
    }
    
    func testURLCacheRequestStreamRemoteOnly() async throws {
        let request = GetGithubUserURLCache()
        
        var resultsCount = 0
        do {
            for try await (response, origin) in request.requestStream(source: .remoteOnly) {
                XCTAssertEqual(response.login, "octocat")
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
        let url = URL(string: "https://api.github.com/users/octocat")!
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
        let url = URL(string: "https://api.github.com/users/octocat")!

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
        let request = GetGithubUserETag(urlCache: urlCache)

        // Primera request — llena el cache con la respuesta y el ETag
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let user):
            XCTAssertEqual(user.login, "octocat")
        case .error(let err):
            XCTFail("First request failed: \(err)")
        }

        try await Task.sleep(nanoseconds: 500_000_000)

        // Segunda request — URLSession envía If-None-Match automáticamente.
        // El servidor responde 304 y URLCache devuelve el cuerpo cacheado de forma transparente.
        let secondResponse = await request.request()
        switch secondResponse {
        case .success(let user):
            XCTAssertEqual(user.login, "octocat", "La segunda request (304 manejado por URLCache) debe devolver los mismos datos")
        case .error(let err):
            XCTFail("Second request (expected transparent 304 cache hit) failed: \(err)")
        }
    }

    /// 4. Verifica que requestStream funciona correctamente con URLCache y ETag.
    func testETagURLCacheRequestStream() async throws {
        let urlCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        let request = GetGithubUserETag(urlCache: urlCache)

        // Primera request — llena el cache
        let _ = await request.request()
        try await Task.sleep(nanoseconds: 500_000_000)

        var resultsCount = 0
        do {
            for try await (response, _) in request.requestStream(source: .remoteOnly) {
                XCTAssertEqual(response.login, "octocat")
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
        let request = GetGithubUserCustomCacheETag()

        let response = await request.request()
        switch response {
        case .success(let user):
            XCTAssertEqual(user.login, "octocat")
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
        let request = GetGithubUserCustomCacheETag()

        // Primera request — llena el cache y guarda el ETag
        let firstResponse = await request.request()
        switch firstResponse {
        case .success(let user):
            XCTAssertEqual(user.login, "octocat")
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
            XCTAssertEqual(user.login, "octocat", "La segunda request (304 + custom cache) debe devolver los mismos datos")
        case .error(let err):
            XCTFail("Second request (expected 304 handled by custom cache) failed: \(err)")
        }
    }
}
