import AppKit
import SwiftUI

struct OutlineSidebar: View {
    let items: [OutlineItem]
    let activeAnchorID: String?
    let onSelect: (OutlineItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Text("No headings")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        OutlineRow(
                            item: item,
                            isActive: item.anchorID == activeAnchorID,
                            onSelect: onSelect
                        )
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 240, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1),
            alignment: .leading
        )
    }
}

struct OutlineRow: View {
    let item: OutlineItem
    let isActive: Bool
    let onSelect: (OutlineItem) -> Void

    private var indent: CGFloat {
        CGFloat(max(item.level - 1, 0)) * 12
    }

    private var fontSize: CGFloat {
        item.level == 1 ? 13 : 12
    }

    private var fontWeight: Font.Weight {
        item.level == 1 ? .semibold : .regular
    }

    private var textColor: Color {
        item.level <= 2 ? .primary : .secondary
    }

    private var activeTextColor: Color {
        isActive ? .accentColor : textColor
    }

    private var activeBackground: Color {
        isActive ? Color.accentColor.opacity(0.18) : .clear
    }

    var body: some View {
        Button(action: {
            onSelect(item)
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(activeTextColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .padding(.leading, indent)
            .padding(.trailing, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(activeBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
