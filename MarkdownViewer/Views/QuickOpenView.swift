import AppKit
import SwiftUI

struct QuickOpenView: View {
    @Binding var isPresented: Bool
    @ObservedObject var recentFilesStore: RecentFilesStore
    let openTabs: [URL]
    let onSelectFile: (URL) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isTextFieldFocused: Bool
    @State private var eventMonitor: Any?

    private var allFiles: [QuickOpenItem] {
        var items: [QuickOpenItem] = []

        // Open tabs first
        for url in openTabs {
            items.append(QuickOpenItem(url: url, isOpenTab: true))
        }

        // Recent files (excluding already open tabs)
        let openPaths = Set(openTabs.map { $0.path })
        for url in recentFilesStore.recentFiles {
            if !openPaths.contains(url.path) {
                items.append(QuickOpenItem(url: url, isOpenTab: false))
            }
        }

        return items
    }

    private var filteredFiles: [QuickOpenItem] {
        if searchText.isEmpty {
            return allFiles
        }
        let query = searchText.lowercased()
        return allFiles.filter { item in
            fuzzyMatch(query: query, target: item.url.lastPathComponent.lowercased())
        }
    }

    private func fuzzyMatch(query: String, target: String) -> Bool {
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        return queryIndex == query.endIndex
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("Search files...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        selectCurrentItem()
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

            // File list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredFiles.isEmpty {
                            Text("No matching files")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                                .padding(16)
                        } else {
                            ForEach(Array(filteredFiles.enumerated()), id: \.element.id) { index, item in
                                QuickOpenRow(
                                    item: item,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    onSelectFile(item.url)
                                    isPresented = false
                                }
                            }
                        }
                    }
                }
                .onChange(of: selectedIndex) { newIndex in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .onAppear {
            selectedIndex = 0
            setupKeyboardMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: searchText) { _ in
            selectedIndex = 0
        }
    }

    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            switch event.keyCode {
            case 126: // Up arrow
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }
                return nil
            case 125: // Down arrow
                if selectedIndex < filteredFiles.count - 1 {
                    selectedIndex += 1
                }
                return nil
            case 53: // Escape
                isPresented = false
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func selectCurrentItem() {
        guard !filteredFiles.isEmpty && selectedIndex < filteredFiles.count else { return }
        onSelectFile(filteredFiles[selectedIndex].url)
        isPresented = false
    }
}

struct QuickOpenItem: Identifiable {
    let id = UUID()
    let url: URL
    let isOpenTab: Bool
}

struct QuickOpenRow: View {
    let item: QuickOpenItem
    let isSelected: Bool

    private var fileName: String {
        item.url.lastPathComponent
    }

    private var filePath: String {
        let path = item.url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isOpenTab ? "doc.text.fill" : "doc.text")
                .font(.system(size: 14))
                .foregroundColor(item.isOpenTab ? .accentColor : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(fileName)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundColor(.primary)

                    if item.isOpenTab {
                        Text("Open")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                Text(filePath)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}
