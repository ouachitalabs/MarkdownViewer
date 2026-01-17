import XCTest
@testable import MarkdownViewer

final class RecentFilesStoreTests: XCTestCase {
    private var originalPaths: [String]?

    override func setUp() {
        super.setUp()
        originalPaths = UserDefaults.standard.stringArray(forKey: "recentFiles")
        UserDefaults.standard.removeObject(forKey: "recentFiles")
        RecentFilesStore.shared.clear()
    }

    override func tearDown() {
        if let originalPaths {
            UserDefaults.standard.set(originalPaths, forKey: "recentFiles")
        } else {
            UserDefaults.standard.removeObject(forKey: "recentFiles")
        }
        super.tearDown()
    }

    func testAddDeduplicatesAndMaintainsOrder() throws {
        let first = try TemporaryFile.create(named: "first.md")
        let second = try TemporaryFile.create(named: "second.md")
        defer {
            first.cleanup()
            second.cleanup()
        }

        let store = RecentFilesStore.shared
        store.add(first.url)
        store.add(second.url)
        store.add(first.url)

        XCTAssertEqual(store.recentFiles, [first.url, second.url])
    }

    func testClearRemovesAll() throws {
        let file = try TemporaryFile.create(named: "doc.md")
        defer {
            file.cleanup()
        }

        let store = RecentFilesStore.shared
        store.add(file.url)
        store.clear()

        XCTAssertTrue(store.recentFiles.isEmpty)
    }

    func testAddTrimsToMaxRecentFiles() throws {
        let store = RecentFilesStore.shared
        var files: [TemporaryFile] = []

        for index in 0..<12 {
            let file = try TemporaryFile.create(named: "file-\(index).md")
            files.append(file)
            store.add(file.url)
        }

        XCTAssertEqual(store.recentFiles.count, 10)
        XCTAssertEqual(store.recentFiles.first, files.last?.url)

        files.forEach { $0.cleanup() }
    }
}
