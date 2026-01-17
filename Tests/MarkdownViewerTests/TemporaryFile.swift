import Foundation

struct TemporaryFile {
    let url: URL
    let directory: URL

    static func create(named name: String = UUID().uuidString) throws -> TemporaryFile {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try "test".write(to: url, atomically: true, encoding: .utf8)
        return TemporaryFile(url: url, directory: directory)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
