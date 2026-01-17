import XCTest
@testable import MarkdownViewer

final class OpenFilesStoreTests: XCTestCase {
    private var originalPaths: [String]?

    override func setUp() {
        super.setUp()
        originalPaths = UserDefaults.standard.stringArray(forKey: "openFiles")
        UserDefaults.standard.removeObject(forKey: "openFiles")
        OpenFilesStore.shared.set([])
    }

    override func tearDown() {
        if let originalPaths {
            UserDefaults.standard.set(originalPaths, forKey: "openFiles")
        } else {
            UserDefaults.standard.removeObject(forKey: "openFiles")
        }
        super.tearDown()
    }

    func testSetDeduplicatesAndFiltersMissingFiles() throws {
        let first = try TemporaryFile.create(named: "first.md")
        let second = try TemporaryFile.create(named: "second.md")
        let missing = first.directory.appendingPathComponent("missing.md")
        defer {
            first.cleanup()
            second.cleanup()
        }

        let store = OpenFilesStore.shared
        store.set([first.url, missing, first.url, second.url])

        XCTAssertEqual(store.openFiles, [first.url, second.url])
    }

    func testSetPreservesOrder() throws {
        let first = try TemporaryFile.create(named: "a.md")
        let second = try TemporaryFile.create(named: "b.md")
        let third = try TemporaryFile.create(named: "c.md")
        defer {
            first.cleanup()
            second.cleanup()
            third.cleanup()
        }

        let store = OpenFilesStore.shared
        store.set([second.url, third.url, first.url])

        XCTAssertEqual(store.openFiles, [second.url, third.url, first.url])
    }
}
