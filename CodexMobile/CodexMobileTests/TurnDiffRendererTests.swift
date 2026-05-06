// FILE: TurnDiffRendererTests.swift
// Purpose: Verifies unified diff line-number parsing used by the diff sheet gutters.
// Layer: Unit Test
// Exports: TurnDiffRendererTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

final class TurnDiffRendererTests: XCTestCase {
    func testLineNumberParserTracksUnifiedDiffRows() {
        let code = """
        @@ -10,3 +10,4 @@
         context
        -removed
        +added
        +addedAgain
         trailing
        """

        let numbers = TurnDiffLineNumberParser.parse(code: code)

        XCTAssertEqual(numbers.count, 6)
        XCTAssertEqual(numbers[0], TurnDiffLineNumbers(old: nil, new: nil))
        XCTAssertEqual(numbers[1], TurnDiffLineNumbers(old: 10, new: 10))
        XCTAssertEqual(numbers[2], TurnDiffLineNumbers(old: 11, new: nil))
        XCTAssertEqual(numbers[3], TurnDiffLineNumbers(old: nil, new: 11))
        XCTAssertEqual(numbers[4], TurnDiffLineNumbers(old: nil, new: 12))
        XCTAssertEqual(numbers[5], TurnDiffLineNumbers(old: 12, new: 13))
    }

    func testLineNumberParserSkipsNoNewlineMarker() {
        let code = """
        @@ -2 +2 @@
        -old
        +new
        \\ No newline at end of file
        """

        let numbers = TurnDiffLineNumberParser.parse(code: code)

        XCTAssertEqual(numbers.count, 4)
        XCTAssertEqual(numbers[0], TurnDiffLineNumbers(old: nil, new: nil))
        XCTAssertEqual(numbers[1], TurnDiffLineNumbers(old: 2, new: nil))
        XCTAssertEqual(numbers[2], TurnDiffLineNumbers(old: nil, new: 2))
        XCTAssertEqual(numbers[3], TurnDiffLineNumbers(old: nil, new: nil))
    }
}
