import Foundation

struct SearchResult: Identifiable {
    let id = UUID()
    let fileURL: URL
    let lineNumber: Int
    let lineContent: String
    let matchRange: Range<String.Index>

    var fileName: String {
        fileURL.lastPathComponent
    }

    var highlightedContent: (before: String, match: String, after: String) {
        let before = String(lineContent[..<matchRange.lowerBound])
        let match = String(lineContent[matchRange])
        let after = String(lineContent[matchRange.upperBound...])
        return (before, match, after)
    }
}

struct FileSearchResults: Identifiable {
    let id = UUID()
    let fileURL: URL
    var results: [SearchResult]

    var fileName: String {
        fileURL.lastPathComponent
    }

    var filePath: String {
        let path = fileURL.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
