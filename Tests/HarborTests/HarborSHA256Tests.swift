//
//  HarborSHA256Tests.swift
//
//
//  Created by Javier Manzo on 26/07/2024.
//

import XCTest
@testable import Harbor

final class HarborSHA256Tests: XCTestCase {
    func testSHA256EmptyData() {
        let data = Data()
        let hash = SHA256.sha256(data: data)
        XCTAssertEqual(hash, "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=", "Hash for empty data is incorrect")
    }

    func testSHA256HelloWorld() {
        let data = "Hello, world!".data(using: .utf8)!
        let hash = SHA256.sha256(data: data)
        XCTAssertEqual(hash, "MV9b23bQeMQ7isAGTkoBZGErH853yGk0W/yUx1iU7dM=", "Hash for 'Hello, world!' is incorrect")
    }

    func testSHA256LongString() {
        let data = String(repeating: "a", count: 1000).data(using: .utf8)!
        let hash = SHA256.sha256(data: data)
        XCTAssertEqual(hash, "Qe3s5C1j6Nm/UVqbppMuHCDLyfWl0TRkWttdsblzfqM=", "Hash for long string is incorrect")
    }
}
