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
        // Set Mock
        let mock = await HMock(request: MockGetRequest<MockModel>.self, statusCode: 401, error: .authNeeded)
        await Harbor.register(mock: mock)

        // Remove Mock
        await Harbor.remove(mock: mock)

        // Request
        let response = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()
        
        // Response
        switch response {
        case .success(let result):
            XCTAssertNotNil(result)
        case .error(let error):
            switch error {
            case .authNeeded:
                XCTFail("Expected success bug got mock error authNeeded")
            default:
                break
            }
        default:
            break
        }
    }
}
