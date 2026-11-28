//
//  HarborImageImportTests.swift
//  HarborImageTests
//
//  `import HarborImage` alone exposes the shared configuration of HarborCore.
//

import XCTest
import HarborImage

@HRequestManagerActor
final class HarborImageImportTests: XCTestCase {

    func testHarborImageReExportsTheSharedConfiguration() async {
        // Given / When
        Harbor.setDefaultTimeoutInterval(15)

        // Then: compiles without importing Harbor or HarborCore
        XCTAssertTrue(true)
    }
}
