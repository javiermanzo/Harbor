//
//  XCTAssertNoThrowAsync.swift
//

import XCTest

/// Async-friendly variant of XCTAssertNoThrow for expressions that `throws` asynchronously.
func XCTAssertNoThrowAsync<T>(_ expression: @autoclosure () async throws -> T,
                              _ message: @autoclosure () -> String = "",
                              file: StaticString = #filePath,
                              line: UInt = #line) async {
    do {
        _ = try await expression()
    } catch {
        XCTFail("Unexpected error thrown: \(error). \(message())", file: file, line: line)
    }
}
