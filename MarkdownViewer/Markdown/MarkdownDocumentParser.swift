import Foundation

struct MarkdownDocumentParser {
    static func parseFrontMatter(_ markdown: String) -> ([(String, String)], String) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---" else { return ([], markdown) }

        var frontMatter: [(String, String)] = []
        var endIndex = 0

        for (index, line) in lines.dropFirst().enumerated() {
            if line == "---" {
                endIndex = index + 2
                break
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    frontMatter.append((key, value))
                }
            }
        }

        let content = lines.dropFirst(endIndex).joined(separator: "\n")
        return (frontMatter, content)
    }

    static func normalizedOutline(_ items: [OutlineItem]) -> [OutlineItem] {
        let h1Count = items.filter { $0.level == 1 }.count
        guard h1Count == 1 else { return items }

        return items.compactMap { item in
            if item.level == 1 {
                return nil
            }
            return OutlineItem(title: item.title, level: max(1, item.level - 1), anchorID: item.anchorID)
        }
    }
}
