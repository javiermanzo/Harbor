//
//  HarborMockTests.swift
//  Harbor
//
//  Created by Javier Manzo on 12/11/2024.
//

import XCTest
@testable import Harbor

@HRequestManagerActor
final class HarborMockTests: XCTestCase {

    override func setUp() async throws {
        Harbor.removeAllMocks()
        Harbor.setMocksEnabled(nil)
    }

    override func tearDown() async throws {
        Harbor.removeAllMocks()
        Harbor.setMocksEnabled(nil)
    }

    func testSuccessMock() async throws {
        let json = """
            {"quote":"For me to say I wasn't a genius I'd just be lying to you and to myself"}
            """
        let mock = HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: json)
        Harbor.register(mock: mock)

        let response = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()

        switch response {
        case .success(let result):
            XCTAssertNotNil(result)
        default:
            XCTFail("Expected success but got an unexpected result")
        }
    }

    func testAuthenticationErrorMock() async throws {
        let mock = HMock(request: MockGetRequest<MockModel>.self, statusCode: 401, error: .authNeeded)
        Harbor.register(mock: mock)

        let response = await MockGetRequest<MockModel>(url: "https://api.kanye.rest/").request()

        switch response {
        case .error(let error):
            guard case .authNeeded = error else {
                return XCTFail("Expected authNeeded but got: \(error)")
            }
        default:
            XCTFail("Expected error authNeeded but got: \(response)")
        }
    }

    func testAddAndRemoveMock() async throws {
        let successMock = HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: """
            {"quote":"Success after mock removal"}
            """)

        // Before registering, no mock is present for the request type.
        XCTAssertFalse(Harbor.isMockRegistered(MockGetRequest<MockModel>.self))

        Harbor.register(mock: successMock)
        XCTAssertTrue(Harbor.isMockRegistered(MockGetRequest<MockModel>.self))

        // Removing the mock clears the registration.
        Harbor.remove(mock: successMock)
        XCTAssertFalse(Harbor.isMockRegistered(MockGetRequest<MockModel>.self))
    }

    func testRemoveAllMocksClearsRegistration() async throws {
        Harbor.register(mock: HMock(request: MockGetRequest<MockModel>.self, statusCode: 200))
        Harbor.register(mock: HMock(request: MockGetRequestWithRetries<MockModel>.self, statusCode: 200))
        XCTAssertEqual(Harbor.isMockRegistered(MockGetRequest<MockModel>.self), true)
        XCTAssertEqual(Harbor.isMockRegistered(MockGetRequestWithRetries<MockModel>.self), true)

        Harbor.removeAllMocks()
        XCTAssertEqual(Harbor.isMockRegistered(MockGetRequest<MockModel>.self), false)
        XCTAssertEqual(Harbor.isMockRegistered(MockGetRequestWithRetries<MockModel>.self), false)
    }

    // MARK: - Call counting

    func testCallCountTracksResolutions() async throws {
        Harbor.setMocksEnabled(true)
        Harbor.register(mock: HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: """
            {"quote":"counted"}
            """))

        XCTAssertEqual(Harbor.mockCallCount(for: MockGetRequest<MockModel>.self), 0)

        _ = await MockGetRequest<MockModel>(url: "https://example.com").request()
        _ = await MockGetRequest<MockModel>(url: "https://example.com").request()

        XCTAssertEqual(Harbor.mockCallCount(for: MockGetRequest<MockModel>.self), 2)
    }

    // MARK: - Sequenced mocks

    func testSequencePlaysResponsesInOrderThenRepeats() async throws {
        Harbor.setMocksEnabled(true)
        Harbor.registerMockSequence(HMockSequence(request: MockGetRequest<MockModel>.self, responses: [
            .init(statusCode: 401, error: .authNeeded),
            .init(statusCode: 200, jsonResponse: """
            {"quote":"then-success"}
            """)
        ]))

        // First resolution: the 401 response.
        let first = await MockGetRequest<MockModel>(url: "https://example.com").request()
        guard case .error(let firstError) = first, case .authNeeded = firstError else {
            return XCTFail("Expected authNeeded first but got: \(first)")
        }

        // Second resolution: the 200 response.
        let second = await MockGetRequest<MockModel>(url: "https://example.com").request()
        guard case .success(let model) = second else {
            return XCTFail("Expected success second but got: \(second)")
        }
        XCTAssertEqual(model.quote, "then-success")

        // Subsequent resolutions repeat the last response.
        let third = await MockGetRequest<MockModel>(url: "https://example.com").request()
        if case .error = third {
            XCTFail("Expected the sequence to repeat its last (success) response but got: \(third)")
        }
    }

    // MARK: - Mocks enabled override

    func testMocksEnabledOverrideForcesMocksOff() async throws {
        Harbor.register(mock: HMock(request: MockGetRequest<MockModel>.self, statusCode: 200, jsonResponse: """
            {"quote":"ignored"}
            """))
        Harbor.setMocksEnabled(false)

        // With mocks forced off, a registered mock is not served: the request reaches the
        // connectivity pre-check and, with no network stub, surfaces a deterministic error.
        let response = await MockGetRequest<MockModel>(url: "https://example.com").request()
        if case .success = response {
            XCTFail("Expected the mock to be ignored while mocks are disabled but got success")
        }
    }
}
