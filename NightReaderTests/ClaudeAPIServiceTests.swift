import XCTest
@testable import NightReader

final class ClaudeAPIServiceTests: XCTestCase {

    // MARK: - JSON Extraction

    func testExtractArrayCleanJSON() throws {
        let response = """
        [{"text":"Sentence one.","type":"thesis","rationale":"Central argument."}]
        """
        let data = try XCTUnwrap(JSONExtractor.extractArray(from: response))
        let results = try JSONDecoder().decode([SmartHighlightResult].self, from: data)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "Sentence one.")
        XCTAssertEqual(results.first?.highlightType, .thesis)
    }

    func testExtractArrayWithMarkdownFences() throws {
        let response = """
        Here are the highlights:

        ```json
        [{"text":"Fenced sentence.","type":"insight","rationale":"Non-obvious."}]
        ```

        Hope that helps!
        """
        let data = try XCTUnwrap(JSONExtractor.extractArray(from: response))
        let results = try JSONDecoder().decode([SmartHighlightResult].self, from: data)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.type, "insight")
    }

    func testExtractArrayWithPreambleText() throws {
        let response = """
        I found these key passages:
        [{"text":"After preamble.","type":"actionable","rationale":"Practical."}]
        """
        let data = try XCTUnwrap(JSONExtractor.extractArray(from: response))
        let results = try JSONDecoder().decode([SmartHighlightResult].self, from: data)
        XCTAssertEqual(results.count, 1)
    }

    func testExtractArrayMalformedReturnsNil() {
        let response = "I couldn't find any key passages in this chapter."
        XCTAssertNil(JSONExtractor.extractArray(from: response))
    }

    func testExtractArrayEmptyArrayReturnsValidData() throws {
        let response = "[]"
        let data = try XCTUnwrap(JSONExtractor.extractArray(from: response))
        let results = try JSONDecoder().decode([SmartHighlightResult].self, from: data)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - SmartHighlightResult parsing

    func testSmartHighlightResultDecoding() throws {
        let json = """
        {"text":"Test sentence.","type":"thesis","rationale":"Core argument of the chapter."}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(SmartHighlightResult.self, from: json)
        XCTAssertEqual(result.text, "Test sentence.")
        XCTAssertEqual(result.type, "thesis")
        XCTAssertEqual(result.rationale, "Core argument of the chapter.")
        XCTAssertEqual(result.highlightType, .thesis)
    }

    func testSmartHighlightResultUnknownTypeFallsBackToInsight() throws {
        let json = """
        {"text":"Unknown type.","type":"mystery","rationale":"Fallback test."}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(SmartHighlightResult.self, from: json)
        XCTAssertEqual(result.highlightType, .insight) // default fallback
    }

    func testMultipleResultsParsing() throws {
        let json = """
        [
            {"text":"First.","type":"thesis","rationale":"R1"},
            {"text":"Second.","type":"insight","rationale":"R2"},
            {"text":"Third.","type":"actionable","rationale":"R3"}
        ]
        """.data(using: .utf8)!
        let results = try JSONDecoder().decode([SmartHighlightResult].self, from: json)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].highlightType, .thesis)
        XCTAssertEqual(results[1].highlightType, .insight)
        XCTAssertEqual(results[2].highlightType, .actionable)
    }
}
