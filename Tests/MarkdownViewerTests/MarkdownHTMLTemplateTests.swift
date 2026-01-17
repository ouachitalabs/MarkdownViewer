import XCTest
@testable import MarkdownViewer

final class MarkdownHTMLTemplateTests: XCTestCase {
    func testRenderReplacesTokens() {
        let html = MarkdownHTMLTemplate.shared.render(body: "<p>Hello</p>", title: "Doc")

        XCTAssertTrue(html.contains("<title>Doc</title>"))
        XCTAssertTrue(html.contains("<p>Hello</p>"))
        XCTAssertFalse(html.contains("__MARKDOWN_VIEWER_TITLE__"))
        XCTAssertFalse(html.contains("__MARKDOWN_VIEWER_BODY__"))
    }

    func testRenderInlinesStylesAndScripts() {
        let html = MarkdownHTMLTemplate.shared.render(body: "<p>Body</p>", title: "Doc")

        XCTAssertTrue(html.contains("--color-canvas-default"))
        XCTAssertTrue(html.contains(".hljs"))
        XCTAssertTrue(html.contains("window.__markdownViewerFind"))
    }
}
