import XCTest
@testable import MarkdownViewer

final class MarkdownDocumentParserTests: XCTestCase {
    func testParseFrontMatterExtractsMetadataAndContent() {
        let input = """
        ---
        title: Hello
        date: 2024-01-01
        ---
        # Heading
        """

        let (frontMatter, content) = MarkdownDocumentParser.parseFrontMatter(input)

        XCTAssertEqual(frontMatter.count, 2)
        XCTAssertEqual(frontMatter[0].0, "title")
        XCTAssertEqual(frontMatter[0].1, "Hello")
        XCTAssertEqual(frontMatter[1].0, "date")
        XCTAssertEqual(frontMatter[1].1, "2024-01-01")
        XCTAssertEqual(content, "# Heading")
    }

    func testParseFrontMatterReturnsOriginalWhenMissingDelimiter() {
        let input = "# Heading\nBody"

        let (frontMatter, content) = MarkdownDocumentParser.parseFrontMatter(input)

        XCTAssertTrue(frontMatter.isEmpty)
        XCTAssertEqual(content, input)
    }

    func testParseFrontMatterSkipsInvalidLines() {
        let input = """
        ---
        title: Hello
        : ignored
        not-a-pair
        ---
        Content
        """

        let (frontMatter, content) = MarkdownDocumentParser.parseFrontMatter(input)

        XCTAssertEqual(frontMatter.count, 1)
        XCTAssertEqual(frontMatter.first?.0, "title")
        XCTAssertEqual(frontMatter.first?.1, "Hello")
        XCTAssertEqual(content, "Content")
    }

    func testParseFrontMatterWithoutClosingDelimiterKeepsOriginalContent() {
        let input = """
        ---
        title: Hello
        Content
        """

        let (frontMatter, content) = MarkdownDocumentParser.parseFrontMatter(input)

        XCTAssertEqual(frontMatter.count, 1)
        XCTAssertEqual(frontMatter.first?.0, "title")
        XCTAssertEqual(frontMatter.first?.1, "Hello")
        XCTAssertEqual(content, input)
    }

    func testParseFrontMatterAllowsColonsInValues() {
        let input = """
        ---
        title: Hello: World
        ---
        Content
        """

        let (frontMatter, content) = MarkdownDocumentParser.parseFrontMatter(input)

        XCTAssertEqual(frontMatter.count, 1)
        XCTAssertEqual(frontMatter.first?.0, "title")
        XCTAssertEqual(frontMatter.first?.1, "Hello: World")
        XCTAssertEqual(content, "Content")
    }

    func testNormalizedOutlineDropsSingleH1AndShiftsLevels() {
        let items = [
            OutlineItem(title: "Title", level: 1, anchorID: "title"),
            OutlineItem(title: "Section", level: 2, anchorID: "section"),
            OutlineItem(title: "Sub", level: 3, anchorID: "sub")
        ]

        let normalized = MarkdownDocumentParser.normalizedOutline(items)

        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(normalized[0].title, "Section")
        XCTAssertEqual(normalized[0].level, 1)
        XCTAssertEqual(normalized[1].title, "Sub")
        XCTAssertEqual(normalized[1].level, 2)
    }

    func testNormalizedOutlineKeepsMultipleH1s() {
        let items = [
            OutlineItem(title: "Intro", level: 1, anchorID: "intro"),
            OutlineItem(title: "Overview", level: 1, anchorID: "overview"),
            OutlineItem(title: "Details", level: 2, anchorID: "details")
        ]

        let normalized = MarkdownDocumentParser.normalizedOutline(items)

        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized[0].level, 1)
        XCTAssertEqual(normalized[1].level, 1)
        XCTAssertEqual(normalized[2].level, 2)
    }
}
