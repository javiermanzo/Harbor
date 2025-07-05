//
//  HarborMockTests.swift
//  Harbor
//
//  Created by Javier Manzo on 12/11/2024.
//

import XCTest
@testable import Harbor

final class HarborMockTests: XCTestCase {

    override func setUp() async throws {
        await Harbor.removeAllMocks()
    }

    func testSuccessMock() async throws {
        // Set Mock
        let json = """
            {"quote":"For me to say I wasn't a genius I'd just be lying to you and to myself"}
            """
        let mock = await HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: json)
        await Harbor.register(mock: mock)

        // Request
        let response = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()

        // Response
        switch response {
        case .success(let result):
            XCTAssertNotNil(result)
        default:
            XCTFail("Expected success but got failure")
        }
    }

    func testAuthenticationErrorMock() async throws {
        // Set Mock
        let mock = await HMock(request: MockGetRequest<MockModel>.self, statusCode: 401, error: .authNeeded)
        await Harbor.register(mock: mock)

        // Request
        let response = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()

        // Response
        switch response {
        case .error(let error):
            switch error {
            case .authNeeded:
                return
            default:
                break
            }
        default:
            break
        }

        XCTFail("Expected error authNeeded")
    }

    func testAddAndRemoveMock() async throws {
        // First, set a mock for success
        let successJson = """
            {"quote":"Success after mock removal"}
            """
        let successMock = await HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: successJson)
        await Harbor.register(mock: successMock)

        // Verify mock is working
        let responseWithMock = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()
        switch responseWithMock {
        case .success(let result):
            XCTAssertNotNil(result)
        case .error:
            XCTFail("Expected success with mock")
        }

        // Remove Mock
        await Harbor.remove(mock: successMock)

        // Register a different mock to verify removal worked
        let errorMock = await HMock(request: MockGetRequest<MockModel>.self, statusCode: 500, error: .noConnectionError)
        await Harbor.register(mock: errorMock)

        // Request should now get the error mock (proving first mock was removed)
        let responseAfterRemoval = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()
        
        // Response should now be the error from the new mock
        switch responseAfterRemoval {
        case .success:
            XCTFail("Expected error from new mock after removal")
        case .error(let error):
            switch error {
            case .noConnectionError:
                // This proves the first mock was removed and second mock is active
                XCTAssertTrue(true)
            default:
                XCTFail("Expected noConnectionError but got: \(error)")
            }
        }
    }
}
