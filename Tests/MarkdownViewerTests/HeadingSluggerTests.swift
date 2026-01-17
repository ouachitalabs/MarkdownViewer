import XCTest
@testable import MarkdownViewer

final class HeadingSluggerTests: XCTestCase {
    func testSlugifyDeduplicatesTitles() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "Hello World"), "hello-world")
        XCTAssertEqual(slugger.slug(for: "Hello World"), "hello-world-1")
    }

    func testSlugifyStripsPunctuation() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "Hello, World!"), "hello-world")
    }

    func testSlugifyFallsBackToSection() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "   "), "section")
    }

    func testSlugifyKeepsNumbers() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "Section 2"), "section-2")
    }

    func testSlugifyIgnoresNonASCIICharacters() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "Café"), "caf")
        XCTAssertEqual(slugger.slug(for: "こんにちは"), "section")
    }

    func testSlugifyCollapsesRepeatedSeparators() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "Hello---World"), "hello-world")
    }
}
