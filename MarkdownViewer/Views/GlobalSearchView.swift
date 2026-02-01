import AppKit
import SwiftUI

struct GlobalSearchView: View {
    @Binding var isPresented: Bool
    @ObservedObject var recentFilesStore: RecentFilesStore
    let onSelectResult: (URL) -> Void

    @State private var searchText = ""
    @State private var searchResults: [FileSearchResults] = []
    @State private var isSearching = false
    @State private var selectedResultIndex: Int?
    @FocusState private var isTextFieldFocused: Bool
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("Search in files...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        performSearch()
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Results list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if searchText.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("Enter a search term to find text in recent files")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                    } else if searchResults.isEmpty && !isSearching {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No results found for \"\(searchText)\"")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                    } else {
                        ForEach(searchResults) { fileResult in
                            FileResultSection(
                                fileResult: fileResult,
                                onSelectResult: { result in
                                    onSelectResult(result.fileURL)
                                    isPresented = false
                                }
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .onAppear {
            setupKeyboardMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: searchText) { newValue in
            if newValue.count >= 2 {
                performSearch()
            } else {
                searchResults = []
            }
        }
    }

    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                isPresented = false
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func performSearch() {
        guard searchText.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true
        let query = searchText.lowercased()
        let files = recentFilesStore.recentFiles

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [FileSearchResults] = []

            for fileURL in files {
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    continue
                }

                let lines = content.components(separatedBy: .newlines)
                var fileResults: [SearchResult] = []

                for (lineIndex, line) in lines.enumerated() {
                    let lowercasedLine = line.lowercased()
                    var searchStartIndex = lowercasedLine.startIndex

                    while let range = lowercasedLine.range(of: query, range: searchStartIndex..<lowercasedLine.endIndex) {
                        // Convert range to original string indices
                        let originalRange = Range(uncheckedBounds: (
                            lower: line.index(line.startIndex, offsetBy: lowercasedLine.distance(from: lowercasedLine.startIndex, to: range.lowerBound)),
                            upper: line.index(line.startIndex, offsetBy: lowercasedLine.distance(from: lowercasedLine.startIndex, to: range.upperBound))
                        ))

                        let result = SearchResult(
                            fileURL: fileURL,
                            lineNumber: lineIndex + 1,
                            lineContent: line.trimmingCharacters(in: .whitespaces),
                            matchRange: originalRange
                        )
                        fileResults.append(result)

                        searchStartIndex = range.upperBound
                    }
                }

                if !fileResults.isEmpty {
                    results.append(FileSearchResults(fileURL: fileURL, results: Array(fileResults.prefix(10))))
                }
            }

            DispatchQueue.main.async {
                searchResults = results
                isSearching = false
            }
        }
    }
}

struct FileResultSection: View {
    let fileResult: FileSearchResults
    let onSelectResult: (SearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)

                Text(fileResult.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Text(fileResult.filePath)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                Text("\(fileResult.results.count) match\(fileResult.results.count == 1 ? "" : "es")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            // Results
            ForEach(fileResult.results) { result in
                SearchResultRow(result: result)
                    .onTapGesture {
                        onSelectResult(result)
                    }
            }
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(result.lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)

            highlightedText
                .font(.system(size: 12))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(Color.clear)
        .onHover { hovering in
            // Visual feedback on hover is handled by background color
        }
    }

    private var highlightedText: some View {
        let parts = result.highlightedContent
        return Text(parts.before)
            .foregroundColor(.primary) +
        Text(parts.match)
            .foregroundColor(.accentColor)
            .fontWeight(.semibold) +
        Text(parts.after)
            .foregroundColor(.primary)
    }
}
