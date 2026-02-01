import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var documentState: DocumentState
    @ObservedObject private var recentFilesStore = RecentFilesStore.shared
    @ObservedObject var appDelegate: AppDelegate
    @State private var isHoveringEdge = false
    @State private var isHoveringSidebar = false
    @State private var isOutlinePinned = false
    @AppStorage("filesSidebarPinned") private var isFilesSidebarPinned = false
    @State private var scrollRequest: ScrollRequest?
    @State private var activeAnchorID: String?

    var onOpenFile: ((URL) -> Void)?

    init(documentState: DocumentState = DocumentState(), appDelegate: AppDelegate, onOpenFile: ((URL) -> Void)? = nil) {
        _documentState = StateObject(wrappedValue: documentState)
        self.appDelegate = appDelegate
        self.onOpenFile = onOpenFile
    }

    private var canShowOutline: Bool {
        !documentState.htmlContent.isEmpty
    }

    private var showPinnedOutline: Bool {
        canShowOutline && isOutlinePinned
    }

    private var showFloatingOutline: Bool {
        canShowOutline && !isOutlinePinned && (isHoveringEdge || isHoveringSidebar)
    }

    @ViewBuilder
    private var documentView: some View {
        if documentState.htmlContent.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Open a Markdown file")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Use File > Open or press \u{2318}O")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WebView(
                htmlContent: documentState.htmlContent,
                scrollRequest: scrollRequest,
                reloadToken: documentState.reloadToken,
                zoomLevel: documentState.zoomLevel,
                contentWidth: documentState.contentWidth,
                findRequest: documentState.findRequest,
                onActiveAnchorChange: { anchorID in
                    activeAnchorID = anchorID
                }
            )
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if isFilesSidebarPinned {
                FilesSidebar(
                    recentFilesStore: recentFilesStore,
                    currentFileURL: documentState.currentURL,
                    onSelectFile: { url in
                        onOpenFile?(url)
                    }
                )
                .transition(.move(edge: .leading))
            }
            documentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showPinnedOutline {
                OutlineSidebar(items: documentState.outlineItems, activeAnchorID: activeAnchorID) { item in
                    scrollRequest = ScrollRequest(id: item.anchorID, token: UUID())
                }
                .transition(.move(edge: .trailing))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .navigationTitle(documentState.title)
        .background(WindowAccessor { window in
            window.tabbingMode = .preferred
            window.documentState = documentState
        })
        .onChange(of: documentState.findQuery) { _ in
            documentState.updateFindResults()
        }
        .onChange(of: documentState.htmlContent) { _ in
            if documentState.isShowingFindBar {
                documentState.updateFindResults()
            }
        }
        .onExitCommand {
            if documentState.isShowingFindBar {
                documentState.hideFindBar()
            }
        }
        .overlay(alignment: .trailing) {
            if canShowOutline && !isOutlinePinned {
                ZStack(alignment: .trailing) {
                    Color.clear
                        .frame(width: 12)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringEdge = hovering
                        }

                    if showFloatingOutline {
                        OutlineSidebar(items: documentState.outlineItems, activeAnchorID: activeAnchorID) { item in
                            scrollRequest = ScrollRequest(id: item.anchorID, token: UUID())
                        }
                        .onHover { hovering in
                            isHoveringSidebar = hovering
                        }
                        .transition(.move(edge: .trailing))
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if documentState.fileChanged || documentState.isShowingFindBar {
                VStack(alignment: .trailing, spacing: 8) {
                    if documentState.fileChanged {
                        Button(action: {
                            documentState.reload()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                                Text("File changed")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    if documentState.isShowingFindBar {
                        FindBar(
                            query: $documentState.findQuery,
                            focusToken: documentState.findFocusToken,
                            onNext: { documentState.findNext() },
                            onPrevious: { documentState.findPrevious() },
                            onClose: { documentState.hideFindBar() }
                        )
                    }
                }
                .padding(12)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFilesSidebarPinned.toggle()
                    }
                }) {
                    Label("Recent Files", systemImage: "sidebar.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.secondary)
                .symbolVariant(isFilesSidebarPinned ? .fill : .none)
                .help(isFilesSidebarPinned ? "Hide Recent Files" : "Show Recent Files")
            }
            if canShowOutline {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isOutlinePinned.toggle()
                        }
                    }) {
                        Label("Table of Contents", systemImage: "sidebar.right")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .symbolVariant(isOutlinePinned ? .fill : .none)
                    .help(isOutlinePinned ? "Hide Table of Contents" : "Show Table of Contents")
                }
            }
        }
        .overlay {
            if appDelegate.isQuickOpenVisible {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            appDelegate.isQuickOpenVisible = false
                        }

                    VStack {
                        QuickOpenView(
                            isPresented: $appDelegate.isQuickOpenVisible,
                            recentFilesStore: recentFilesStore,
                            openTabs: appDelegate.getOpenTabs(),
                            onSelectFile: { url in
                                onOpenFile?(url)
                            }
                        )
                        .padding(.top, 80)
                        Spacer()
                    }
                }
            }
        }
        .overlay {
            if appDelegate.isGlobalSearchVisible {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            appDelegate.isGlobalSearchVisible = false
                        }

                    VStack {
                        GlobalSearchView(
                            isPresented: $appDelegate.isGlobalSearchVisible,
                            recentFilesStore: recentFilesStore,
                            onSelectResult: { url in
                                onOpenFile?(url)
                            }
                        )
                        .padding(.top, 80)
                        Spacer()
                    }
                }
            }
        }
    }
}
