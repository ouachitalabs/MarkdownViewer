import AppKit
import SwiftUI

struct FindBar: View {
    @Binding var query: String
    let focusToken: UUID
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .focused($isFocused)
                .onSubmit {
                    onNext()
                }
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor))
        )
        .cornerRadius(8)
        .shadow(radius: 6)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: focusToken) { _ in
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onExitCommand {
            onClose()
        }
    }
}
