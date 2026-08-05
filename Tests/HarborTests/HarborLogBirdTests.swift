//
//  HarborLogBirdTests.swift
//  Harbor
//

import XCTest
import Combine
import LogBird
@testable import Harbor

final class HarborLogBirdTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        await Harbor.setLoggingEnabled(true)
        await HLogger.logger.clearLogs()
        await Harbor.loggingSensitiveKeys(.reset)
    }

    override func tearDown() async throws {
        await Harbor.setLoggingEnabled(true)
        await HLogger.logger.clearLogs()
        await Harbor.loggingSensitiveKeys(.reset)
        cancellables.removeAll()
    }

    // MARK: - Default Sensitive Keys

    func testInheritsLogBirdDefaultSensitiveKeys() async {
        // Harbor no longer registers its own keys: LogBird 2.1's expanded global
        // defaults (password, token, authorization, auth, secret, apikey, cookie,
        // bearer, credentials, privatekey) already cover HTTP auth fields.
        let keys = await HLogger.sensitiveKeys
        XCTAssertTrue(LogBird.defaultSensitiveKeys.isSubset(of: keys))
    }

    // MARK: - .set (replace semantics)

    func testSetReplacesEntireSensitiveKeySet() async {
        await Harbor.loggingSensitiveKeys(.set(["only_this"]))

        let keys = await HLogger.sensitiveKeys
        // Keys are normalized at insertion (lowercased, stripping -, _ and whitespace).
        XCTAssertEqual(keys, Set(["onlythis"]))
        XCTAssertFalse(keys.contains("token"), "Defaults should not be merged back in")
        XCTAssertFalse(keys.contains("auth"))
    }

    func testClearDisablesRedactionForDebugging() async {
        // Disabling redaction entirely so tokens are visible while debugging.
        await Harbor.loggingSensitiveKeys(.clear)

        let info: [String: LBValue] = [
            "username": .string("johndoe"),
            "authToken": .string("secret_bearer_token_12345"),
            "password": .string("P@ssw0rd123!")
        ]

        await HLogger.log("Authentication Attempt", additionalInfo: info)

        let logs = await HLogger.logger.logs
        guard let lastLog = logs.last, let stored = lastLog.additionalInfo else {
            XCTFail("Expected a recorded log with additionalInfo")
            return
        }

        XCTAssertEqual(stored["username"]?.description, "johndoe")
        XCTAssertEqual(stored["authToken"]?.description, "secret_bearer_token_12345",
                       "Token should be visible when redaction is disabled")
        XCTAssertEqual(stored["password"]?.description, "P@ssw0rd123!",
                       "Password should be visible when redaction is disabled")
    }

    // MARK: - .add (extend semantics)

    func testAddExtendsActiveSensitiveKeySet() async {
        await Harbor.loggingSensitiveKeys(.add(["trace_id", "token"])) // "token" is already a default

        let keys = await HLogger.sensitiveKeys
        // Inserted keys are normalized (lowercased, stripping -, _ and whitespace).
        XCTAssertTrue(keys.contains("traceid"), "trace_id should be normalized to traceid")
        // Defaults are preserved when extending.
        XCTAssertTrue(keys.contains("auth"))
    }

    // MARK: - .reset

    func testResetRestoresLogBirdDefaults() async {
        await Harbor.loggingSensitiveKeys(.set(["custom"]))
        await Harbor.loggingSensitiveKeys(.reset)

        let keys = await HLogger.sensitiveKeys
        XCTAssertEqual(keys, LogBird.defaultSensitiveKeys)
        XCTAssertTrue(keys.contains("auth"))
        XCTAssertFalse(keys.contains("custom"))
    }

    // MARK: - Redaction reaches Harbor's logger (bug-fix coverage)

    func testHLoggerRedactsHTTPAuthFields() async {
        // LogBird 2.1's global defaults + separator-insensitive matching cover
        // these HTTP fields, and Harbor's logger inherits them — so they are
        // redacted on the same instance Harbor logs through.
        let info: [String: LBValue] = [
            "username": .string("johndoe"),
            "set-cookie": .string("session=abc; Path=/"),
            "x-api-key": .string("key_99887766"),
            "authorization": .string("Bearer secret"),
            "refresh_token": .string("rt_abcdef")
        ]

        await HLogger.log("Outbound Request", additionalInfo: info)

        let logs = await HLogger.logger.logs
        guard let lastLog = logs.last, let stored = lastLog.additionalInfo else {
            XCTFail("Expected a recorded log with additionalInfo")
            return
        }

        XCTAssertEqual(stored["username"]?.description, "johndoe")
        XCTAssertEqual(stored["set-cookie"]?.description, "<redacted>")
        XCTAssertEqual(stored["x-api-key"]?.description, "<redacted>")
        XCTAssertEqual(stored["authorization"]?.description, "<redacted>")
        XCTAssertEqual(stored["refresh_token"]?.description, "<redacted>")
    }

    // MARK: - Typed metadata (LBValue)

    func testTypedLBValueMetadata() async {
        let metadata: [String: LBValue] = [
            "endpoint": .string("https://api.example.com/v1/data"),
            "statusCode": .int(200),
            "isSuccess": .bool(true),
            "latency": .double(45.2)
        ]
        let extra = [LBExtraMessage(key: "Headers", value: "Content-Type: application/json")]

        await HLogger.log("API Log", extraMessages: extra, additionalInfo: metadata, level: .info)

        let logs = await HLogger.logger.logs
        guard let log = logs.last else {
            XCTFail("Log should exist")
            return
        }

        XCTAssertEqual(log.level, .info)
        XCTAssertEqual(log.extraMessages?.first?.key, "Headers")
        XCTAssertEqual(log.extraMessages?.first?.value, "Content-Type: application/json")
        if case .int(let code) = log.additionalInfo?["statusCode"] {
            XCTAssertEqual(code, 200)
        } else {
            XCTFail("Expected .int statusCode")
        }
        if case .bool(let success) = log.additionalInfo?["isSuccess"] {
            XCTAssertEqual(success, true)
        } else {
            XCTFail("Expected .bool isSuccess")
        }
    }

    // MARK: - Combine publisher

    func testLogsPublisherEmitsLogEvents() async {
        let expectation = expectation(description: "Receive LBLogEvent.recorded event")

        await HLogger.logger.logsPublisher
            .sink { event in
                switch event {
                case .recorded(let log):
                    if log.message == "Publisher Test Log" {
                        expectation.fulfill()
                    }
                case .cleared:
                    break
                }
            }
            .store(in: &cancellables)

        await HLogger.log("Publisher Test Log", level: .warning)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - Logging Enabled / Disabled

    func testLoggingDisabledSuppressesLogOutput() async {
        await Harbor.setLoggingEnabled(false)
        await HLogger.log("Should not be logged", level: .info)

        let logs = await HLogger.logger.logs
        XCTAssertTrue(logs.isEmpty, "No logs should be recorded when logging is disabled")
    }

    @HRequestManagerActor
    private static func getIsLoggingEnabled() -> Bool {
        HConfig.shared.isLoggingEnabled
    }

    func testDefaultIsLoggingEnabledInDebug() async {
        let isEnabled = await Self.getIsLoggingEnabled()
        #if DEBUG
        XCTAssertTrue(isEnabled, "isLoggingEnabled should default to true in DEBUG builds")
        #else
        XCTAssertFalse(isEnabled, "isLoggingEnabled should default to false in RELEASE builds")
        #endif
    }
}
