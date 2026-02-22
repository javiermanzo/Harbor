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
}
