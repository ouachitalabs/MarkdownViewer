import AppKit
import SwiftUI

struct FilesSidebar: View {
    @ObservedObject var recentFilesStore: RecentFilesStore
    let currentFileURL: URL?
    let onSelectFile: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Files")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                if recentFilesStore.recentFiles.isEmpty {
                    Text("No recent files")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(recentFilesStore.recentFiles, id: \.self) { url in
                        FileRow(
                            url: url,
                            isSelected: url == currentFileURL,
                            onSelect: { onSelectFile(url) }
                        )
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 200, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

struct FileRow: View {
    let url: URL
    let isSelected: Bool
    let onSelect: () -> Void

    private var fileIcon: String {
        "doc.text"
    }

    private var fileName: String {
        url.lastPathComponent
    }

    private var filePath: String {
        let path = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: fileIcon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(fileName)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(filePath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
