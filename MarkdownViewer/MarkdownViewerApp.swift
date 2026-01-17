import SwiftUI
import Markdown
import WebKit
import ObjectiveC

@main
struct MarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var recentFilesStore = RecentFilesStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appDelegate.openFileFromPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    ForEach(recentFilesStore.recentFiles, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            appDelegate.openFile(at: url)
                        }
                    }
                    if !recentFilesStore.recentFiles.isEmpty {
                        Divider()
                        Button("Clear Menu") {
                            recentFilesStore.clear()
                        }
                    }
                }
            }
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    appDelegate.openEmptyTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Next Tab") {
                    appDelegate.selectNextTab()
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .keyboardShortcut(.tab, modifiers: .control)

                Button("Previous Tab") {
                    appDelegate.selectPreviousTab()
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                ForEach(1...9, id: \.self) { index in
                    Button("Show Tab \(index)") {
                        appDelegate.selectTab(at: index - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }

                Button("Reload") {
                    appDelegate.reloadActiveDocument()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Divider()

                Button("Find...") {
                    appDelegate.showFindBar()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    appDelegate.findNext()
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    appDelegate.findPrevious()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    appDelegate.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    appDelegate.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    appDelegate.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [ViewerWindowController] = []
    private let openFilesStore = OpenFilesStore.shared
    private var windowCloseObserver: Any?
    private var keyDownMonitor: Any?
    private var didRestoreOpenFiles = false
    private var isTerminating = false

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            openFile(at: url)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.handleWindowWillClose(window)
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.control) else { return event }
            guard !flags.contains(.command), !flags.contains(.option) else { return event }
            guard event.keyCode == 48 else { return event }
            guard self.activeDocumentWindow() != nil else { return event }
            if flags.contains(.shift) {
                self.selectPreviousTab()
            } else {
                self.selectNextTab()
            }
            return nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.restoreOpenFilesIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openEmptyTab()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        persistOpenFilesFromWindows()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !isTerminating {
            persistOpenFilesFromWindows()
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    func openFileFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openFile(at: url)
        }
    }

    func openFile(at url: URL) {
        if let documentState = reusableEmptyDocumentState() {
            documentState.loadFile(at: url)
            focusWindow(for: documentState)
            return
        }

        openInNewTab(url: url)
    }

    func openEmptyTab() {
        openInNewTab(url: nil)
    }

    func reloadActiveDocument() {
        activeDocumentState()?.reload()
    }

    func zoomIn() {
        activeDocumentState()?.zoomIn()
    }

    func zoomOut() {
        activeDocumentState()?.zoomOut()
    }

    func resetZoom() {
        activeDocumentState()?.resetZoom()
    }

    func showFindBar() {
        activeDocumentState()?.showFindBar()
    }

    func findNext() {
        activeDocumentState()?.findNext()
    }

    func findPrevious() {
        activeDocumentState()?.findPrevious()
    }

    func selectNextTab() {
        activeDocumentWindow()?.selectNextTab(nil)
    }

    func selectPreviousTab() {
        activeDocumentWindow()?.selectPreviousTab(nil)
    }

    func selectTab(at index: Int) {
        guard let window = activeDocumentWindow() else { return }
        let tabs = tabGroupWindows(for: window)
        guard tabs.indices.contains(index) else { return }
        tabs[index].makeKeyAndOrderFront(nil)
    }

    private func activeDocumentState() -> DocumentState? {
        if let state = NSApplication.shared.keyWindow?.documentState {
            return state
        }
        if let state = NSApplication.shared.mainWindow?.documentState {
            return state
        }
        return NSApplication.shared.windows.compactMap(\.documentState).first
    }

    private func activeDocumentWindow() -> NSWindow? {
        if let window = NSApplication.shared.keyWindow, window.documentState != nil {
            return window
        }
        if let window = NSApplication.shared.mainWindow, window.documentState != nil {
            return window
        }
        return NSApplication.shared.windows.first { $0.documentState != nil }
    }

    private func reusableEmptyDocumentState() -> DocumentState? {
        if let active = activeDocumentState(), active.currentURL == nil {
            return active
        }
        return NSApplication.shared.windows
            .compactMap(\.documentState)
            .first { $0.currentURL == nil }
    }

    private func focusWindow(for documentState: DocumentState) {
        if let window = NSApplication.shared.windows.first(where: { $0.documentState === documentState }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func tabGroupWindows(for window: NSWindow) -> [NSWindow] {
        let tabs = window.tabbedWindows ?? []
        return tabs.isEmpty ? [window] : tabs
    }

    private func restoreOpenFilesIfNeeded() {
        guard !didRestoreOpenFiles else { return }
        let urls = openFilesStore.openFiles
        guard !urls.isEmpty else { return }
        guard NSApplication.shared.windows.contains(where: { $0.documentState != nil }) else {
            DispatchQueue.main.async { [weak self] in
                self?.restoreOpenFilesIfNeeded()
            }
            return
        }
        didRestoreOpenFiles = true
        let existing = Set(currentOpenFileURLs().map { $0.path })
        for url in urls where !existing.contains(url.path) {
            openFile(at: url)
        }
    }

    private func handleWindowWillClose(_ window: NSWindow) {
        guard window.documentState != nil else { return }
        if isTerminating { return }
        let documentWindows = NSApplication.shared.windows.filter { $0.documentState != nil }
        if documentWindows.count == 1 && documentWindows.first === window {
            openFilesStore.set(currentOpenFileURLs())
            return
        }
        let remaining = documentWindows
            .filter { $0 !== window }
            .compactMap { $0.documentState?.currentURL }
        openFilesStore.set(remaining)
    }

    private func persistOpenFilesFromWindows() {
        openFilesStore.set(currentOpenFileURLs())
    }

    private func currentOpenFileURLs() -> [URL] {
        NSApplication.shared.windows.compactMap { $0.documentState?.currentURL }
    }

    private func openInNewTab(url: URL?) {
        let documentState = DocumentState()
        if let url {
            documentState.loadFile(at: url)
        }

        openWindow(with: documentState)
    }

    private func openWindow(with documentState: DocumentState) {
        let contentView = ContentView(documentState: documentState)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 600, height: 400))
        window.tabbingMode = .preferred
        window.title = documentState.title
        window.documentState = documentState

        let windowController = ViewerWindowController(window: window)
        window.delegate = windowController
        windowController.onClose = { [weak self, weak windowController] in
            guard let windowController else { return }
            self?.windowControllers.removeAll { $0 === windowController }
        }
        if let tabGroupWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            tabGroupWindow.addTabbedWindow(window, ordered: .above)
        }
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        windowControllers.append(windowController)
    }
}

final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private var documentStateKey: UInt8 = 0

private let commentHeaderPrefix = "<!-- MarkdownViewer comments:"
private let commentHeaderLine = "<!-- MarkdownViewer comments: Do not remove MV-COMMENT markers. They anchor inline comments. -->"

private extension NSWindow {
    var documentState: DocumentState? {
        get {
            objc_getAssociatedObject(self, &documentStateKey) as? DocumentState
        }
        set {
            objc_setAssociatedObject(self, &documentStateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

final class RecentFilesStore: ObservableObject {
    static let shared = RecentFilesStore()

    @Published private(set) var recentFiles: [URL] = []
    private let maxRecentFiles = 10
    private let defaultsKey = "recentFiles"

    private init() {
        load()
    }

    func add(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        save()
    }

    func clear() {
        recentFiles = []
        save()
    }

    private func save() {
        let paths = recentFiles.map { $0.path }
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    private func load() {
        if let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            recentFiles = paths.compactMap { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
}

final class OpenFilesStore: ObservableObject {
    static let shared = OpenFilesStore()

    @Published private(set) var openFiles: [URL] = []
    private let defaultsKey = "openFiles"

    private init() {
        load()
    }

    func set(_ urls: [URL]) {
        openFiles = normalize(urls)
        save()
    }

    private func save() {
        let paths = openFiles.map { $0.path }
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    private func load() {
        if let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) {
            openFiles = normalize(paths.map { URL(fileURLWithPath: $0) })
        }
    }

    private func normalize(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let path = url.path
            guard !seen.contains(path) else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            seen.insert(path)
            result.append(url)
        }
        return result
    }
}

class DocumentState: ObservableObject {
    @Published var htmlContent: String = ""
    @Published var title: String = "Markdown Viewer"
    @Published var fileChanged: Bool = false
    @Published var outlineItems: [OutlineItem] = []
    @Published var comments: [MarkdownComment] = []
    @Published var reloadToken: UUID?
    @Published var zoomLevel: CGFloat = 1.0
    @Published var isShowingFindBar: Bool = false
    @Published var findQuery: String = ""
    @Published var findRequest: FindRequest?
    @Published var findFocusToken: UUID = UUID()
    var currentURL: URL?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var lastModificationDate: Date?
    private let recentFilesStore: RecentFilesStore
    private var markdownSource: String = ""

    init(recentFilesStore: RecentFilesStore = .shared) {
        self.recentFilesStore = recentFilesStore
    }

    deinit {
        stopMonitoring()
    }

    func loadFile(at url: URL) {
        currentURL = url
        fileChanged = false
        startMonitoring(url: url)
        recentFilesStore.add(url)
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let frontMatterInfo = parseFrontMatter(markdown)
            let content = frontMatterInfo.content
            let document = Document(parsing: content)
            var renderer = MarkdownRenderer(source: content, sourceOffsetBase: frontMatterInfo.contentStartOffset)
            let rendered = renderer.render(document)
            let frontMatterHTML = renderFrontMatter(frontMatterInfo.items)
            self.htmlContent = wrapInHTML(frontMatterHTML + rendered.html, title: url.lastPathComponent)
            self.title = url.lastPathComponent
            self.outlineItems = normalizedOutline(rendered.outline)
            self.comments = parseComments(from: markdown)
            self.markdownSource = markdown
        } catch {
            self.htmlContent = wrapInHTML("<p>Error loading file: \(error.localizedDescription)</p>", title: "Error")
            self.title = "Error"
            self.outlineItems = []
            self.comments = []
            self.markdownSource = ""
        }
    }

    private func parseFrontMatter(_ markdown: String) -> FrontMatterInfo {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---" else {
            return FrontMatterInfo(items: [], content: markdown, contentStartOffset: 0, frontMatterEndOffset: 0)
        }

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
        let contentStartIndex = contentStartIndex(in: markdown, endIndex: endIndex)
        let contentStartOffset = markdown.utf8.distance(from: markdown.utf8.startIndex, to: contentStartIndex)
        return FrontMatterInfo(
            items: frontMatter,
            content: content,
            contentStartOffset: contentStartOffset,
            frontMatterEndOffset: contentStartOffset
        )
    }

    private func contentStartIndex(in markdown: String, endIndex: Int) -> String.Index {
        guard endIndex > 0 else { return markdown.startIndex }
        var index = markdown.startIndex
        var linesToSkip = endIndex
        while linesToSkip > 0, index < markdown.endIndex {
            guard let newlineIndex = markdown[index...].firstIndex(of: "\n") else {
                return markdown.endIndex
            }
            index = markdown.index(after: newlineIndex)
            linesToSkip -= 1
        }
        return index
    }

    private func renderFrontMatter(_ frontMatter: [(String, String)]) -> String {
        guard !frontMatter.isEmpty else { return "" }

        var html = """
        <div class="front-matter" data-mv-frontmatter="true">
        <table class="front-matter-table">
        """
        for (key, value) in frontMatter {
            let displayKey = key.replacingOccurrences(of: "_", with: " ").capitalized
            html += "<tr><td class=\"fm-key\">\(escapeHTML(displayKey))</td><td class=\"fm-value\">\(escapeHTML(value))</td></tr>\n"
        }
        html += "</table></div>\n"
        return html
    }

    private func normalizedOutline(_ items: [OutlineItem]) -> [OutlineItem] {
        let h1Count = items.filter { $0.level == 1 }.count
        guard h1Count == 1 else { return items }

        return items.compactMap { item in
            if item.level == 1 {
                return nil
            }
            return OutlineItem(title: item.title, level: max(1, item.level - 1), anchorID: item.anchorID)
        }
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func addComment(startOffset: Int, endOffset: Int, body: String) {
        guard let url = currentURL else { return }
        guard startOffset < endOffset else { return }
        do {
            var markdown = try String(contentsOf: url, encoding: .utf8)
            let frontMatterInfo = parseFrontMatter(markdown)
            let headerResult = ensureCommentHeader(in: markdown, insertionOffset: frontMatterInfo.frontMatterEndOffset)
            markdown = headerResult.markdown

            var adjustedStart = startOffset
            var adjustedEnd = endOffset
            if headerResult.insertedBytes > 0 {
                if startOffset >= headerResult.insertionOffset {
                    adjustedStart += headerResult.insertedBytes
                }
                if endOffset >= headerResult.insertionOffset {
                    adjustedEnd += headerResult.insertedBytes
                }
            }

            let existingComments = parseComments(from: markdown)
            let newID = nextCommentID(from: existingComments)
            let now = Date()
            let comment = MarkdownComment(id: newID, created: now, updated: now, body: body)

            guard let updatedMarkdown = insertCommentMarkers(
                in: markdown,
                startOffset: adjustedStart,
                endOffset: adjustedEnd,
                comment: comment
            ) else {
                return
            }
            try updatedMarkdown.write(to: url, atomically: true, encoding: .utf8)
            loadFile(at: url)
        } catch {
            return
        }
    }

    func updateComment(id: String, body: String) {
        guard let url = currentURL else { return }
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            guard let updatedMarkdown = updatingCommentPayload(in: markdown, id: id, body: body) else {
                return
            }
            try updatedMarkdown.write(to: url, atomically: true, encoding: .utf8)
            loadFile(at: url)
        } catch {
            return
        }
    }

    func deleteComment(id: String) {
        guard let url = currentURL else { return }
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            guard let updatedMarkdown = removingCommentMarkers(in: markdown, id: id) else {
                return
            }
            try updatedMarkdown.write(to: url, atomically: true, encoding: .utf8)
            loadFile(at: url)
        } catch {
            return
        }
    }

    private func parseComments(from markdown: String) -> [MarkdownComment] {
        let pattern = "<!--\\s*MV-COMMENT-START\\s+({.*?})\\s*-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: range)
        var comments: [MarkdownComment] = []

        for match in matches {
            guard match.numberOfRanges > 1,
                  let jsonRange = Range(match.range(at: 1), in: markdown) else {
                continue
            }
            let json = String(markdown[jsonRange])
            if let comment = CommentCodec.decode(json: json) {
                comments.append(comment)
            }
        }

        return comments.sorted { $0.numericID < $1.numericID }
    }

    private func nextCommentID(from comments: [MarkdownComment]) -> String {
        let maxID = comments.map(\.numericID).max() ?? 0
        return "COM-\(maxID + 1)"
    }

    private func ensureCommentHeader(in markdown: String, insertionOffset: Int) -> (markdown: String, insertedBytes: Int, insertionOffset: Int) {
        if markdown.contains(commentHeaderPrefix) {
            return (markdown, 0, insertionOffset)
        }
        let header = commentHeaderLine + "\n\n"
        guard let insertIndex = indexForUTF8Offset(insertionOffset, in: markdown) else {
            return (markdown, 0, insertionOffset)
        }
        let updated = String(markdown[..<insertIndex]) + header + String(markdown[insertIndex...])
        return (updated, header.utf8.count, insertionOffset)
    }

    private func insertCommentMarkers(in markdown: String, startOffset: Int, endOffset: Int, comment: MarkdownComment) -> String? {
        guard let startIndex = indexForUTF8Offset(startOffset, in: markdown),
              let endIndex = indexForUTF8Offset(endOffset, in: markdown),
              startIndex <= endIndex,
              let payload = CommentCodec.encode(comment: comment) else {
            return nil
        }
        let startMarker = "<!-- MV-COMMENT-START \(payload) -->"
        let endMarker = "<!-- MV-COMMENT-END \(comment.id) -->"
        let before = markdown[..<startIndex]
        let middle = markdown[startIndex..<endIndex]
        let after = markdown[endIndex...]
        return String(before) + startMarker + String(middle) + endMarker + String(after)
    }

    private func updatingCommentPayload(in markdown: String, id: String, body: String) -> String? {
        let pattern = "<!--\\s*MV-COMMENT-START\\s+({.*?})\\s*-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: range)
        let mutable = NSMutableString(string: markdown)

        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let jsonRange = match.range(at: 1)
            let json = (markdown as NSString).substring(with: jsonRange)
            guard let existing = CommentCodec.decode(json: json), existing.id == id else {
                continue
            }
            let updated = MarkdownComment(id: existing.id, created: existing.created, updated: Date(), body: body)
            guard let payload = CommentCodec.encode(comment: updated) else { continue }
            let replacement = "<!-- MV-COMMENT-START \(payload) -->"
            mutable.replaceCharacters(in: match.range, with: replacement)
            return mutable as String
        }
        return nil
    }

    private func removingCommentMarkers(in markdown: String, id: String) -> String? {
        let startPattern = "<!--\\s*MV-COMMENT-START\\s+({.*?})\\s*-->"
        guard let startRegex = try? NSRegularExpression(pattern: startPattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        let matches = startRegex.matches(in: markdown, options: [], range: range)
        let mutable = NSMutableString(string: markdown)
        var removed = false

        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let jsonRange = match.range(at: 1)
            let json = (markdown as NSString).substring(with: jsonRange)
            guard let existing = CommentCodec.decode(json: json), existing.id == id else {
                continue
            }
            mutable.replaceCharacters(in: match.range, with: "")
            removed = true
            break
        }

        guard removed else { return nil }
        let endPattern = "<!--\\s*MV-COMMENT-END\\s+\(NSRegularExpression.escapedPattern(for: id))\\s*-->"
        guard let endRegex = try? NSRegularExpression(pattern: endPattern, options: []) else {
            return mutable as String
        }
        let current = mutable as String
        let endRange = NSRange(current.startIndex..<current.endIndex, in: current)
        let result = endRegex.stringByReplacingMatches(in: current, options: [], range: endRange, withTemplate: "")
        return result
    }

    private func indexForUTF8Offset(_ offset: Int, in string: String) -> String.Index? {
        guard offset >= 0 else { return nil }
        let utf8 = string.utf8
        guard offset <= utf8.count else { return nil }
        let utf8Index = utf8.index(utf8.startIndex, offsetBy: offset)
        return utf8Index.samePosition(in: string)
    }

    func reload() {
        guard let url = currentURL else { return }
        reloadToken = UUID()
        loadFile(at: url)
    }

    func zoomIn() {
        zoomLevel = min(zoomLevel + 0.1, 3.0)
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel - 0.1, 0.5)
    }

    func resetZoom() {
        zoomLevel = 1.0
    }

    func showFindBar() {
        let wasShowing = isShowingFindBar
        isShowingFindBar = true
        findFocusToken = UUID()
        if !wasShowing {
            updateFindResults()
        }
    }

    func hideFindBar() {
        isShowingFindBar = false
        clearFindHighlights()
    }

    func updateFindResults() {
        requestFind(direction: .forward, reset: true)
    }

    func findNext() {
        requestFind(direction: .forward, reset: false)
    }

    func findPrevious() {
        requestFind(direction: .backward, reset: false)
    }

    private func startMonitoring(url: URL) {
        stopMonitoring()

        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        lastModificationDate = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        fileMonitor?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let newModDate = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            if newModDate != self.lastModificationDate {
                self.fileChanged = true
            }
        }

        fileMonitor?.setCancelHandler {
            close(fileDescriptor)
        }

        fileMonitor?.resume()
    }

    private func stopMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    private func requestFind(direction: FindDirection, reset: Bool) {
        let trimmed = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findRequest = FindRequest(query: "", direction: .forward, token: UUID(), reset: true)
            return
        }
        findRequest = FindRequest(query: trimmed, direction: direction, token: UUID(), reset: reset)
    }

    private func clearFindHighlights() {
        findRequest = FindRequest(query: "", direction: .forward, token: UUID(), reset: true)
    }

    private func wrapInHTML(_ body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title)</title>
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css" media="(prefers-color-scheme: light)">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" media="(prefers-color-scheme: dark)">
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <style>
                :root {
                    color-scheme: light dark;
                    --color-fg-default: #1f2328;
                    --color-fg-muted: #656d76;
                    --color-canvas-default: #ffffff;
                    --color-canvas-subtle: #f6f8fa;
                    --color-border-default: #d0d7de;
                    --color-border-muted: hsla(210,18%,87%,1);
                    --color-accent-fg: #0969da;
                    --color-danger-fg: #d1242f;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --color-fg-default: #e6edf3;
                        --color-fg-muted: #8d96a0;
                        --color-canvas-default: #0d1117;
                        --color-canvas-subtle: #161b22;
                        --color-border-default: #30363d;
                        --color-border-muted: #21262d;
                        --color-accent-fg: #4493f8;
                        --color-danger-fg: #f85149;
                    }
                }
                * { box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans', Helvetica, Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.5;
                    word-wrap: break-word;
                    max-width: 980px;
                    margin: 0 auto;
                    padding: 32px 28px;
                    background-color: var(--color-canvas-default);
                    color: var(--color-fg-default);
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                h1 { font-size: 2em; padding-bottom: 0.3em; border-bottom: 1px solid var(--color-border-muted); }
                h2 { font-size: 1.5em; padding-bottom: 0.3em; border-bottom: 1px solid var(--color-border-muted); }
                h3 { font-size: 1.25em; }
                h4 { font-size: 1em; }
                h5 { font-size: 0.875em; }
                h6 { font-size: 0.85em; color: var(--color-fg-muted); }
                p { margin-top: 0; margin-bottom: 10px; }
                a {
                    color: var(--color-accent-fg);
                    text-decoration: none;
                }
                a:hover { text-decoration: underline; }
                code {
                    font-family: ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace;
                    font-size: 85%;
                    padding: 0.2em 0.4em;
                    margin: 0;
                    background-color: var(--color-canvas-subtle);
                    border-radius: 6px;
                }
                pre {
                    margin-top: 0;
                    margin-bottom: 16px;
                    padding: 16px;
                    overflow: auto;
                    font-size: 85%;
                    line-height: 1.45;
                    background-color: var(--color-canvas-subtle);
                    border-radius: 6px;
                }
                pre code {
                    display: block;
                    padding: 0;
                    margin: 0;
                    overflow: visible;
                    line-height: inherit;
                    word-wrap: normal;
                    background-color: transparent;
                    border: 0;
                    font-size: 100%;
                }
                blockquote {
                    margin: 0 0 16px 0;
                    padding: 0 1em;
                    color: var(--color-fg-muted);
                    border-left: 0.25em solid var(--color-border-default);
                }
                blockquote > :first-child { margin-top: 0; }
                blockquote > :last-child { margin-bottom: 0; }
                ul, ol {
                    margin-top: 0;
                    margin-bottom: 16px;
                    padding-left: 2em;
                }
                li { margin-top: 0.25em; }
                li + li { margin-top: 0.25em; }
                ul ul, ul ol, ol ol, ol ul {
                    margin-top: 0;
                    margin-bottom: 0;
                }
                hr {
                    height: 0.25em;
                    padding: 0;
                    margin: 24px 0;
                    background-color: var(--color-border-default);
                    border: 0;
                }
                table {
                    border-spacing: 0;
                    border-collapse: collapse;
                    margin-top: 0;
                    margin-bottom: 16px;
                    display: block;
                    width: max-content;
                    max-width: 100%;
                    overflow: auto;
                }
                table th {
                    font-weight: 600;
                }
                table th, table td {
                    padding: 6px 13px;
                    border: 1px solid var(--color-border-default);
                }
                table tr {
                    background-color: var(--color-canvas-default);
                    border-top: 1px solid var(--color-border-muted);
                }
                table tr:nth-child(2n) {
                    background-color: var(--color-canvas-subtle);
                }
                img {
                    max-width: 100%;
                    box-sizing: content-box;
                    background-color: var(--color-canvas-default);
                }
                del { color: var(--color-fg-muted); }
                strong { font-weight: 600; }
                em { font-style: italic; }
                .front-matter {
                    margin-bottom: 24px;
                    padding: 12px 16px;
                    background-color: var(--color-canvas-subtle);
                    border-radius: 6px;
                    border: 1px solid var(--color-border-muted);
                }
                .front-matter-table {
                    display: table;
                    width: auto;
                    margin: 0;
                    font-size: 12px;
                    border: none;
                }
                .front-matter-table tr {
                    background: transparent !important;
                    border: none;
                }
                .front-matter-table td {
                    padding: 2px 0;
                    border: none;
                    vertical-align: top;
                }
                .front-matter-table .fm-key {
                    color: var(--color-fg-muted);
                    padding-right: 12px;
                    white-space: nowrap;
                    font-weight: 500;
                }
                .front-matter-table .fm-value {
                    color: var(--color-fg-default);
                    font-family: ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace;
                }
                .mv-comment-highlight {
                    background-color: rgba(255, 230, 153, 0.6);
                    border-radius: 4px;
                    padding: 0 2px;
                    cursor: pointer;
                    box-decoration-break: clone;
                    -webkit-box-decoration-break: clone;
                }
                .mv-comment-highlight:hover {
                    background-color: rgba(255, 214, 102, 0.7);
                }
                #mv-comment-action {
                    position: fixed;
                    z-index: 9999;
                    padding: 6px 10px;
                    border-radius: 999px;
                    border: 1px solid var(--color-border-default);
                    background-color: var(--color-canvas-default);
                    color: var(--color-fg-default);
                    font-size: 12px;
                    font-weight: 600;
                    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.12);
                    display: none;
                    cursor: pointer;
                    user-select: none;
                }
                #mv-comment-action:hover {
                    border-color: var(--color-accent-fg);
                    color: var(--color-accent-fg);
                }
                @media (prefers-color-scheme: dark) {
                    .mv-comment-highlight {
                        background-color: rgba(255, 205, 87, 0.25);
                    }
                    .mv-comment-highlight:hover {
                        background-color: rgba(255, 205, 87, 0.4);
                    }
                }
                mark.mv-find-match {
                    background-color: #fff3b0;
                    color: #111111;
                    border-radius: 2px;
                }
                mark.mv-find-active {
                    background-color: #ffd24d;
                }
            </style>
        </head>
        <body>
            <div id="mv-document">
                \(body)
            </div>
            <script>hljs.highlightAll();</script>
            <script>
                (function() {
                    var state = {
                        query: "",
                        matches: [],
                        index: -1
                    };

                    function clearHighlights() {
                        var marks = document.querySelectorAll("mark.mv-find-match");
                        for (var i = 0; i < marks.length; i++) {
                            var mark = marks[i];
                            var parent = mark.parentNode;
                            if (!parent) {
                                continue;
                            }
                            parent.replaceChild(document.createTextNode(mark.textContent), mark);
                            parent.normalize();
                        }
                        state.matches = [];
                        state.index = -1;
                    }

                    function collectTextNodes() {
                        var nodes = [];
                        var root = document.getElementById("mv-document") || document.body;
                        var walker = document.createTreeWalker(
                            root,
                            NodeFilter.SHOW_TEXT,
                            {
                                acceptNode: function(node) {
                                    if (!node.nodeValue || !node.nodeValue.trim()) {
                                        return NodeFilter.FILTER_REJECT;
                                    }
                                    var parent = node.parentNode;
                                    if (!parent) {
                                        return NodeFilter.FILTER_REJECT;
                                    }
                                    if (parent.closest("script, style, mark")) {
                                        return NodeFilter.FILTER_REJECT;
                                    }
                                    return NodeFilter.FILTER_ACCEPT;
                                }
                            }
                        );
                        var current = walker.nextNode();
                        while (current) {
                            nodes.push(current);
                            current = walker.nextNode();
                        }
                        return nodes;
                    }

                    function highlightAll(query) {
                        clearHighlights();
                        state.query = query;
                        if (!query) {
                            return;
                        }
                        var lowerQuery = query.toLowerCase();
                        var nodes = collectTextNodes();
                        for (var i = 0; i < nodes.length; i++) {
                            var node = nodes[i];
                            var text = node.nodeValue;
                            var fragment = document.createDocumentFragment();
                            var lowerText = text.toLowerCase();
                            var startIndex = 0;
                            var matchIndex = lowerText.indexOf(lowerQuery, startIndex);
                            if (matchIndex === -1) {
                                continue;
                            }
                            while (matchIndex !== -1) {
                                var endIndex = matchIndex + query.length;
                                if (matchIndex > startIndex) {
                                    fragment.appendChild(document.createTextNode(text.slice(startIndex, matchIndex)));
                                }
                                var mark = document.createElement("mark");
                                mark.className = "mv-find-match";
                                mark.textContent = text.slice(matchIndex, endIndex);
                                fragment.appendChild(mark);
                                state.matches.push(mark);
                                startIndex = endIndex;
                                matchIndex = lowerText.indexOf(lowerQuery, startIndex);
                            }
                            if (startIndex < text.length) {
                                fragment.appendChild(document.createTextNode(text.slice(startIndex)));
                            }
                            node.parentNode.replaceChild(fragment, node);
                        }
                        if (state.matches.length > 0) {
                            state.index = 0;
                            updateActive();
                        }
                    }

                    function updateActive() {
                        if (state.matches.length === 0 || state.index < 0) {
                            return;
                        }
                        for (var i = 0; i < state.matches.length; i++) {
                            if (i === state.index) {
                                state.matches[i].classList.add("mv-find-active");
                            } else {
                                state.matches[i].classList.remove("mv-find-active");
                            }
                        }
                        var target = state.matches[state.index];
                        if (target && target.scrollIntoView) {
                            target.scrollIntoView({ block: "center", inline: "nearest" });
                        }
                    }

                    function step(direction) {
                        if (state.matches.length === 0) {
                            return;
                        }
                        if (direction === "backward") {
                            state.index = (state.index - 1 + state.matches.length) % state.matches.length;
                        } else {
                            state.index = (state.index + 1) % state.matches.length;
                        }
                        updateActive();
                    }

                    window.__markdownViewerFind = function(payload) {
                        if (!payload) {
                            return;
                        }
                        var query = payload.query || "";
                        var direction = payload.direction || "forward";
                        var reset = Boolean(payload.reset);
                        if (reset || query !== state.query) {
                            highlightAll(query);
                        } else {
                            step(direction);
                        }
                    };
                })();
                (function() {
                    function utf8Length(text) {
                        return new TextEncoder().encode(text).length;
                    }

                    function findTextSpan(node) {
                        if (!node) {
                            return null;
                        }
                        if (node.nodeType === Node.TEXT_NODE) {
                            if (!node.parentElement) {
                                return null;
                            }
                            return node.parentElement.closest("[data-mv-text-start]");
                        }
                        if (node.nodeType === Node.ELEMENT_NODE) {
                            return node.closest("[data-mv-text-start]");
                        }
                        return null;
                    }

                    function isDisallowedSelection(node) {
                        if (!node || !node.parentElement) {
                            return false;
                        }
                        return Boolean(node.parentElement.closest("code, pre, a, [data-mv-frontmatter]"));
                    }

                    var lastSelectionInfo = null;
                    var commentAction = null;

                    function ensureCommentAction() {
                        if (commentAction) {
                            return commentAction;
                        }
                        commentAction = document.createElement("button");
                        commentAction.id = "mv-comment-action";
                        commentAction.type = "button";
                        commentAction.textContent = "Comment";
                        commentAction.addEventListener("mousedown", function(event) {
                            event.preventDefault();
                        });
                        commentAction.addEventListener("click", function(event) {
                            event.stopPropagation();
                            if (!lastSelectionInfo) {
                                hideCommentAction();
                                return;
                            }
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentSelection) {
                                window.webkit.messageHandlers.commentSelection.postMessage(lastSelectionInfo);
                            }
                            hideCommentAction();
                        });
                        document.body.appendChild(commentAction);
                        return commentAction;
                    }

                    function showCommentAction(rect) {
                        var action = ensureCommentAction();
                        var width = action.offsetWidth || 90;
                        var height = action.offsetHeight || 28;
                        var x = rect.x + rect.width + 8;
                        var y = rect.y - 4;
                        x = Math.min(x, window.innerWidth - width - 8);
                        y = Math.min(y, window.innerHeight - height - 8);
                        x = Math.max(8, x);
                        y = Math.max(8, y);
                        action.style.left = x + "px";
                        action.style.top = y + "px";
                        action.style.display = "block";
                    }

                    function hideCommentAction() {
                        if (commentAction) {
                            commentAction.style.display = "none";
                        }
                    }

                    function updateCommentAction() {
                        var info = getSelectionInfo();
                        if (info && !info.error) {
                            lastSelectionInfo = info;
                            showCommentAction(info.rect);
                        } else {
                            lastSelectionInfo = null;
                            hideCommentAction();
                        }
                    }

                    function getSelectionInfo() {
                        var selection = window.getSelection();
                        if (!selection || selection.rangeCount === 0) {
                            return { error: "Select text to add a comment." };
                        }
                        var range = selection.getRangeAt(0);
                        if (range.collapsed) {
                            return { error: "Select text to add a comment." };
                        }
                        if (isDisallowedSelection(range.startContainer) || isDisallowedSelection(range.endContainer)) {
                            return { error: "Comments aren't supported inside code, links, or front matter." };
                        }
                        var startSpan = findTextSpan(range.startContainer);
                        var endSpan = findTextSpan(range.endContainer);
                        if (!startSpan || !endSpan) {
                            return { error: "Selection must be inside the document body." };
                        }
                        var startBase = parseInt(startSpan.dataset.mvTextStart || "0", 10);
                        var endBase = parseInt(endSpan.dataset.mvTextStart || "0", 10);
                        var startText = range.startContainer.nodeType === Node.TEXT_NODE ? (range.startContainer.nodeValue || "") : "";
                        var endText = range.endContainer.nodeType === Node.TEXT_NODE ? (range.endContainer.nodeValue || "") : "";
                        var startOffset = startBase + utf8Length(startText.slice(0, range.startOffset));
                        var endOffset = endBase + utf8Length(endText.slice(0, range.endOffset));
                        if (!Number.isFinite(startOffset) || !Number.isFinite(endOffset) || endOffset <= startOffset) {
                            return { error: "Selection isn't valid for comments." };
                        }
                        var rect = range.getBoundingClientRect();
                        return {
                            start: startOffset,
                            end: endOffset,
                            text: selection.toString(),
                            rect: {
                                x: rect.x,
                                y: rect.y,
                                width: rect.width,
                                height: rect.height
                            }
                        };
                    }

                    function clearCommentHighlights() {
                        var highlights = document.querySelectorAll("span.mv-comment-highlight");
                        for (var i = highlights.length - 1; i >= 0; i--) {
                            var highlight = highlights[i];
                            var parent = highlight.parentNode;
                            if (!parent) {
                                continue;
                            }
                            while (highlight.firstChild) {
                                parent.insertBefore(highlight.firstChild, highlight);
                            }
                            parent.removeChild(highlight);
                            parent.normalize();
                        }
                    }

                    function applyCommentHighlights() {
                        clearCommentHighlights();
                        var root = document.getElementById("mv-document") || document.body;
                        if (!root) {
                            return;
                        }
                        var walker = document.createTreeWalker(root, NodeFilter.SHOW_COMMENT, null, false);
                        var starts = {};
                        var ends = {};
                        var payloads = {};
                        var node;
                        while ((node = walker.nextNode())) {
                            var text = (node.nodeValue || "").trim();
                            if (text.indexOf("MV-COMMENT-START") === 0) {
                                var jsonText = text.slice("MV-COMMENT-START".length).trim();
                                try {
                                    var payload = JSON.parse(jsonText);
                                    if (payload && payload.id) {
                                        starts[payload.id] = node;
                                        payloads[payload.id] = jsonText;
                                    }
                                } catch (e) {
                                }
                            } else if (text.indexOf("MV-COMMENT-END") === 0) {
                                var id = text.slice("MV-COMMENT-END".length).trim();
                                if (id) {
                                    ends[id] = node;
                                }
                            }
                        }

                        Object.keys(starts).forEach(function(id) {
                            var startNode = starts[id];
                            var endNode = ends[id];
                            if (!startNode || !endNode) {
                                return;
                            }
                            var range = document.createRange();
                            range.setStartAfter(startNode);
                            range.setEndBefore(endNode);
                            var wrapper = document.createElement("span");
                            wrapper.className = "mv-comment-highlight";
                            wrapper.dataset.commentId = id;
                            if (payloads[id]) {
                                wrapper.dataset.commentPayload = payloads[id];
                            }
                            var fragment = range.extractContents();
                            wrapper.appendChild(fragment);
                            range.insertNode(wrapper);
                        });
                    }

                    function sendCommentTapped(target) {
                        if (!target) {
                            return;
                        }
                        var rect = target.getBoundingClientRect();
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commentTapped) {
                            window.webkit.messageHandlers.commentTapped.postMessage({
                                id: target.dataset.commentId || "",
                                payload: target.dataset.commentPayload || "",
                                rect: {
                                    x: rect.x,
                                    y: rect.y,
                                    width: rect.width,
                                    height: rect.height
                                }
                            });
                        }
                    }

                    document.addEventListener("click", function(event) {
                        var target = event.target;
                        if (!target) {
                            return;
                        }
                        var highlight = target.closest(".mv-comment-highlight");
                        if (highlight) {
                            sendCommentTapped(highlight);
                        }
                    });

                    document.addEventListener("selectionchange", function() {
                        updateCommentAction();
                    });

                    window.addEventListener("scroll", function() {
                        hideCommentAction();
                    }, true);

                    window.addEventListener("resize", function() {
                        hideCommentAction();
                    });

                    window.__markdownViewerComments = {
                        getSelection: getSelectionInfo,
                        refresh: applyCommentHighlights
                    };

                    applyCommentHighlights();
                })();
            </script>
        </body>
        </html>
        """
    }
}

struct OutlineItem: Identifiable {
    let id = UUID()
    let title: String
    let level: Int
    let anchorID: String
}

struct FrontMatterInfo {
    let items: [(String, String)]
    let content: String
    let contentStartOffset: Int
    let frontMatterEndOffset: Int
}

struct MarkdownComment: Identifiable, Equatable {
    let id: String
    let created: Date
    let updated: Date
    let body: String

    var numericID: Int {
        let parts = id.split(separator: "-")
        if parts.count == 2, let number = Int(parts[1]) {
            return number
        }
        return 0
    }
}

struct CommentPayload: Codable {
    let id: String
    let created: String
    let updated: String
    let bodyB64: String
}

enum CommentCodec {
    static func encode(comment: MarkdownComment) -> String? {
        let formatter = ISO8601DateFormatter()
        let payload = CommentPayload(
            id: comment.id,
            created: formatter.string(from: comment.created),
            updated: formatter.string(from: comment.updated),
            bodyB64: Data(comment.body.utf8).base64EncodedString()
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(json: String) -> MarkdownComment? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CommentPayload.self, from: data) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        guard let created = formatter.date(from: payload.created),
              let updated = formatter.date(from: payload.updated),
              let bodyData = Data(base64Encoded: payload.bodyB64),
              let body = String(data: bodyData, encoding: .utf8) else {
            return nil
        }
        return MarkdownComment(id: payload.id, created: created, updated: updated, body: body)
    }
}

struct RenderedMarkdown {
    let html: String
    let outline: [OutlineItem]
}

struct SourceMapper {
    private let lineStartOffsets: [Int]

    init(source: String) {
        var offsets: [Int] = [0]
        var index = 0
        for byte in source.utf8 {
            if byte == 10 {
                offsets.append(index + 1)
            }
            index += 1
        }
        self.lineStartOffsets = offsets
    }

    func offset(for location: SourceLocation) -> Int? {
        guard location.line > 0, location.line <= lineStartOffsets.count else { return nil }
        let lineStart = lineStartOffsets[location.line - 1]
        let columnOffset = max(0, location.column - 1)
        return lineStart + columnOffset
    }
}

struct HeadingSlugger {
    private var counts: [String: Int] = [:]

    mutating func slug(for title: String) -> String {
        let base = slugify(title)
        let key = base.isEmpty ? "section" : base
        let count = counts[key, default: 0]
        counts[key] = count + 1
        if count == 0 {
            return key
        }
        return "\(key)-\(count)"
    }

    private func slugify(_ title: String) -> String {
        let lowercased = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = ""
        var needsHyphen = false

        for scalar in lowercased.unicodeScalars {
            guard scalar.isASCII else {
                needsHyphen = true
                continue
            }
            let value = scalar.value
            let isLetter = value >= 97 && value <= 122
            let isDigit = value >= 48 && value <= 57
            if isLetter || isDigit {
                if needsHyphen && !result.isEmpty {
                    result.append("-")
                }
                needsHyphen = false
                result.append(Character(scalar))
            } else {
                needsHyphen = true
            }
        }

        return result
    }
}

struct MarkdownRenderer: MarkupWalker {
    var result = ""
    var outline: [OutlineItem] = []
    var slugger = HeadingSlugger()
    private let sourceMapper: SourceMapper?
    private let sourceOffsetBase: Int

    init(source: String, sourceOffsetBase: Int) {
        self.sourceMapper = SourceMapper(source: source)
        self.sourceOffsetBase = sourceOffsetBase
    }

    init() {
        self.sourceMapper = nil
        self.sourceOffsetBase = 0
    }

    mutating func render(_ document: Document) -> RenderedMarkdown {
        result = ""
        outline = []
        slugger = HeadingSlugger()
        for child in document.children {
            visit(child)
        }
        return RenderedMarkdown(html: result, outline: outline)
    }

    mutating func visit(_ markup: any Markup) {
        switch markup {
        case let heading as Heading:
            let title = heading.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let anchorID = slugger.slug(for: title)
            if !title.isEmpty {
                outline.append(OutlineItem(title: title, level: heading.level, anchorID: anchorID))
            }
            result += "<h\(heading.level) id=\"\(anchorID)\">"
            for child in heading.children { visit(child) }
            result += "</h\(heading.level)>\n"
        case let paragraph as Paragraph:
            result += "<p>"
            for child in paragraph.children { visit(child) }
            result += "</p>\n"
        case let text as Markdown.Text:
            appendText(text)
        case let emphasis as Emphasis:
            result += "<em>"
            for child in emphasis.children { visit(child) }
            result += "</em>"
        case let strong as Strong:
            result += "<strong>"
            for child in strong.children { visit(child) }
            result += "</strong>"
        case let code as InlineCode:
            result += "<code>\(escapeHTML(code.code))</code>"
        case let codeBlock as CodeBlock:
            let lang = codeBlock.language ?? ""
            result += "<pre><code class=\"language-\(lang)\">\(escapeHTML(codeBlock.code))</code></pre>\n"
        case let link as Markdown.Link:
            result += "<a href=\"\(link.destination ?? "")\">"
            for child in link.children { visit(child) }
            result += "</a>"
        case let image as Markdown.Image:
            let alt = image.plainText
            result += "<img src=\"\(image.source ?? "")\" alt=\"\(escapeHTML(alt))\">"
        case let list as UnorderedList:
            result += "<ul>\n"
            for child in list.children { visit(child) }
            result += "</ul>\n"
        case let list as OrderedList:
            result += "<ol>\n"
            for child in list.children { visit(child) }
            result += "</ol>\n"
        case let item as ListItem:
            result += "<li>"
            for child in item.children { visit(child) }
            result += "</li>\n"
        case let quote as BlockQuote:
            result += "<blockquote>\n"
            for child in quote.children { visit(child) }
            result += "</blockquote>\n"
        case is ThematicBreak:
            result += "<hr>\n"
        case is SoftBreak:
            result += " "
        case is LineBreak:
            result += "<br>\n"
        case let table as Markdown.Table:
            result += "<table>\n"
            let head = table.head
            result += "<thead><tr>\n"
            for cell in head.cells {
                result += "<th>"
                for child in cell.children { visit(child) }
                result += "</th>\n"
            }
            result += "</tr></thead>\n"
            result += "<tbody>\n"
            for row in table.body.rows {
                result += "<tr>\n"
                for cell in row.cells {
                    result += "<td>"
                    for child in cell.children { visit(child) }
                    result += "</td>\n"
                }
                result += "</tr>\n"
            }
            result += "</tbody></table>\n"
        case let strikethrough as Strikethrough:
            result += "<del>"
            for child in strikethrough.children { visit(child) }
            result += "</del>"
        case let htmlBlock as HTMLBlock:
            if shouldRenderHTML(htmlBlock.rawHTML) {
                result += htmlBlock.rawHTML
            }
        case let inlineHTML as InlineHTML:
            if shouldRenderHTML(inlineHTML.rawHTML) {
                result += inlineHTML.rawHTML
            }
        default:
            for child in markup.children {
                visit(child)
            }
        }
    }

    private mutating func appendText(_ text: Markdown.Text) {
        let escaped = escapeHTML(text.string)
        guard let range = text.range,
              let mapper = sourceMapper,
              let start = mapper.offset(for: range.lowerBound),
              let end = mapper.offset(for: range.upperBound) else {
            result += escaped
            return
        }
        let startOffset = start + sourceOffsetBase
        let endOffset = end + sourceOffsetBase
        result += "<span data-mv-text-start=\"\(startOffset)\" data-mv-text-end=\"\(endOffset)\">"
        result += escaped
        result += "</span>"
    }

    private func shouldRenderHTML(_ html: String) -> Bool {
        html.contains("MV-COMMENT-") || html.contains(commentHeaderPrefix)
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowResolverView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            onResolve(window)
        }
    }
}

final class WindowResolverView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onResolve?(window)
        }
    }
}

struct ContentView: View {
    @StateObject private var documentState: DocumentState
    @State private var isHoveringEdge = false
    @State private var isHoveringSidebar = false
    @State private var isOutlinePinned = false
    @State private var scrollRequest: ScrollRequest?
    @State private var commentPopover: CommentPopoverState?
    @State private var commentSelectionRequest: UUID?
    @State private var commentError: String?
    @State private var commentErrorTask: DispatchWorkItem?

    init(documentState: DocumentState = DocumentState()) {
        _documentState = StateObject(wrappedValue: documentState)
    }

    private var canShowOutline: Bool {
        !documentState.htmlContent.isEmpty
    }

    private var canShowComments: Bool {
        !documentState.htmlContent.isEmpty
    }

    private var showOutline: Bool {
        guard canShowOutline else { return false }
        return isOutlinePinned || isHoveringEdge || isHoveringSidebar
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
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
                        findRequest: documentState.findRequest,
                        commentSelectionRequest: commentSelectionRequest,
                        commentPopover: commentPopover,
                        onCommentSelection: { selection in
                            commentPopover = CommentPopoverState(token: UUID(), anchorRect: selection.rect, mode: .add(selection))
                        },
                        onCommentSelectionError: { message in
                            showCommentError(message)
                        },
                        onCommentTapped: { id, rect, payloadComment in
                            let comment = payloadComment ?? documentState.comments.first(where: { $0.id == id })
                            guard let comment else { return }
                            commentPopover = CommentPopoverState(token: UUID(), anchorRect: rect, mode: .edit(comment))
                        },
                        onAddComment: { selection, body in
                            documentState.addComment(startOffset: selection.start, endOffset: selection.end, body: body)
                        },
                        onUpdateComment: { id, body in
                            documentState.updateComment(id: id, body: body)
                        },
                        onDeleteComment: { id in
                            documentState.deleteComment(id: id)
                        },
                        onDismissCommentPopover: {
                            commentPopover = nil
                        }
                    )
                }
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
            commentPopover = nil
        }
        .onExitCommand {
            if documentState.isShowingFindBar {
                documentState.hideFindBar()
            }
        }
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                Color.clear
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHoveringEdge = hovering
                    }

                if showOutline {
                    OutlineSidebar(items: documentState.outlineItems) { item in
                        scrollRequest = ScrollRequest(id: item.anchorID, token: UUID())
                    }
                    .onHover { hovering in
                        isHoveringSidebar = hovering
                    }
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if documentState.fileChanged || documentState.isShowingFindBar || commentError != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    if let commentError {
                        Text(commentError)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
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
            if canShowComments {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        requestCommentSelection()
                    }) {
                        Label("Add Comment", systemImage: "text.bubble")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .help("Add Comment")
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                }
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
    }

    private func requestCommentSelection() {
        commentSelectionRequest = UUID()
    }

    private func showCommentError(_ message: String) {
        commentError = message
        commentErrorTask?.cancel()
        let task = DispatchWorkItem {
            commentError = nil
        }
        commentErrorTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }
}

struct OutlineSidebar: View {
    let items: [OutlineItem]
    let onSelect: (OutlineItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Text("No headings")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        OutlineRow(item: item, onSelect: onSelect)
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

    var body: some View {
        Button(action: {
            onSelect(item)
        }) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(textColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .padding(.leading, indent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

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

struct CommentEditorView: View {
    let mode: CommentPopoverMode
    let onSave: (String) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void
    @State private var commentText: String

    init(mode: CommentPopoverMode, onSave: @escaping (String) -> Void, onDelete: (() -> Void)?, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        switch mode {
        case .add(let selection):
            _commentText = State(initialValue: "")
            self.selectedText = selection.text
            self.commentID = nil
            self.createdAt = nil
            self.updatedAt = nil
        case .edit(let comment):
            _commentText = State(initialValue: comment.body)
            self.selectedText = nil
            self.commentID = comment.id
            self.createdAt = comment.created
            self.updatedAt = comment.updated
        }
    }

    private let selectedText: String?
    private let commentID: String?
    private let createdAt: Date?
    private let updatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(modeTitle)
                    .font(.headline)
                Spacer()
                if let commentID {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commentID, forType: .string)
                    }) {
                        HStack(spacing: 4) {
                            Text(commentID)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Copy Comment ID")
                }
            }

            if let selectedText, !selectedText.isEmpty {
                Text(selectedText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            TextEditor(text: $commentText)
                .font(.system(size: 12))
                .frame(width: 280, height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor))
                )

            if let createdAt, let updatedAt {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created \(formatDate(createdAt))")
                    Text("Edited \(formatDate(updatedAt))")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                Spacer()
                if let onDelete {
                    Button("Delete") {
                        onDelete()
                    }
                }
                Button("Save") {
                    onSave(commentText)
                }
            }
        }
        .padding(12)
    }

    private var modeTitle: String {
        switch mode {
        case .add:
            return "Add Comment"
        case .edit:
            return "Comment"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ScrollRequest: Equatable {
    let id: String
    let token: UUID
}

enum FindDirection: Equatable {
    case forward
    case backward
}

struct FindRequest: Equatable {
    let query: String
    let direction: FindDirection
    let token: UUID
    let reset: Bool
}

struct FindPayload: Encodable {
    let query: String
    let direction: String
    let reset: Bool
}

struct CommentSelection: Equatable {
    let start: Int
    let end: Int
    let text: String
    let rect: CGRect
}

struct CommentSelectionError: Error {
    let message: String
}

enum CommentPopoverMode: Equatable {
    case add(CommentSelection)
    case edit(MarkdownComment)
}

struct CommentPopoverState: Equatable {
    let token: UUID
    let anchorRect: CGRect
    let mode: CommentPopoverMode
}

struct WebView: NSViewRepresentable {
    let htmlContent: String
    let scrollRequest: ScrollRequest?
    let reloadToken: UUID?
    let zoomLevel: CGFloat
    let findRequest: FindRequest?
    let commentSelectionRequest: UUID?
    let commentPopover: CommentPopoverState?
    let onCommentSelection: (CommentSelection) -> Void
    let onCommentSelectionError: (String) -> Void
    let onCommentTapped: (String, CGRect, MarkdownComment?) -> Void
    let onAddComment: (CommentSelection, String) -> Void
    let onUpdateComment: (String, String) -> Void
    let onDeleteComment: (String) -> Void
    let onDismissCommentPopover: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "commentTapped")
        userContentController.add(context.coordinator, name: "commentSelection")
        config.userContentController = userContentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCommentSelection = onCommentSelection
        context.coordinator.onCommentSelectionError = onCommentSelectionError
        context.coordinator.onCommentTapped = onCommentTapped
        context.coordinator.onAddComment = onAddComment
        context.coordinator.onUpdateComment = onUpdateComment
        context.coordinator.onDeleteComment = onDeleteComment
        context.coordinator.onDismissCommentPopover = onDismissCommentPopover

        if htmlContent != context.coordinator.lastHTML {
            let shouldPreserveScroll = reloadToken != nil && reloadToken != context.coordinator.lastReloadToken
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.lastHTML = htmlContent
            context.coordinator.isLoading = true

            if shouldPreserveScroll {
                let coordinator = context.coordinator
                webView.evaluateJavaScript("window.scrollY") { result, _ in
                    coordinator.savedScrollY = (result as? CGFloat) ?? 0
                    webView.loadHTMLString(htmlContent, baseURL: nil)
                }
            } else {
                webView.loadHTMLString(htmlContent, baseURL: nil)
            }
        }

        if let request = scrollRequest {
            context.coordinator.requestScroll(request, in: webView)
        }

        if zoomLevel != context.coordinator.lastZoomLevel {
            context.coordinator.lastZoomLevel = zoomLevel
            let percentage = Int(zoomLevel * 100)
            webView.evaluateJavaScript("document.body.style.zoom = '\(percentage)%'", completionHandler: nil)
        }

        if let request = findRequest {
            context.coordinator.requestFind(request, in: webView)
        }

        if let request = commentSelectionRequest,
           request != context.coordinator.lastCommentSelectionRequest {
            context.coordinator.lastCommentSelectionRequest = request
            context.coordinator.requestCommentSelection(in: webView)
        }

        if let popover = commentPopover {
            context.coordinator.showCommentPopover(popover, in: webView)
        } else {
            context.coordinator.closeCommentPopover()
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSPopoverDelegate {
        var lastHTML: String?
        var pendingAnchor: String?
        var pendingToken: UUID?
        var lastHandledToken: UUID?
        var isLoading = false
        var lastReloadToken: UUID?
        var savedScrollY: CGFloat = 0
        var lastZoomLevel: CGFloat = 1.0
        var pendingFindRequest: FindRequest?
        var lastFindToken: UUID?
        var lastCommentSelectionRequest: UUID?
        var commentPopover: NSPopover?
        var lastPopoverToken: UUID?
        var onCommentSelection: ((CommentSelection) -> Void)?
        var onCommentSelectionError: ((String) -> Void)?
        var onCommentTapped: ((String, CGRect, MarkdownComment?) -> Void)?
        var onAddComment: ((CommentSelection, String) -> Void)?
        var onUpdateComment: ((String, String) -> Void)?
        var onDeleteComment: ((String) -> Void)?
        var onDismissCommentPopover: (() -> Void)?

        func requestScroll(_ request: ScrollRequest, in webView: WKWebView) {
            guard request.token != lastHandledToken else { return }
            pendingAnchor = request.id
            pendingToken = request.token
            if !isLoading {
                performScroll(in: webView)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false

            if lastZoomLevel != 1.0 {
                let percentage = Int(lastZoomLevel * 100)
                webView.evaluateJavaScript("document.body.style.zoom = '\(percentage)%'", completionHandler: nil)
            }

            if savedScrollY > 0 {
                let scrollY = savedScrollY
                savedScrollY = 0
                webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))", completionHandler: nil)
            }

            performScroll(in: webView)
            performFind(in: webView)
        }

        private func performScroll(in webView: WKWebView) {
            guard let anchor = pendingAnchor, let token = pendingToken else { return }
            pendingAnchor = nil
            pendingToken = nil
            lastHandledToken = token

            let escaped = anchor
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let script = "var el = document.getElementById('\(escaped)'); if (el) { el.scrollIntoView(); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func requestFind(_ request: FindRequest, in webView: WKWebView) {
            guard request.token != lastFindToken else { return }
            lastFindToken = request.token
            pendingFindRequest = request
            if !isLoading {
                performFind(in: webView)
            }
        }

        private func performFind(in webView: WKWebView) {
            guard let request = pendingFindRequest else { return }
            pendingFindRequest = nil
            let payload = FindPayload(
                query: request.query,
                direction: request.direction == .backward ? "backward" : "forward",
                reset: request.reset
            )
            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            webView.evaluateJavaScript("window.__markdownViewerFind(\(json));", completionHandler: nil)
        }

        func requestCommentSelection(in webView: WKWebView) {
            let script = "window.__markdownViewerComments && window.__markdownViewerComments.getSelection ? window.__markdownViewerComments.getSelection() : null"
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    self.onCommentSelectionError?(error.localizedDescription)
                    return
                }
                switch self.parseCommentSelection(result) {
                case .success(let selection):
                    self.onCommentSelection?(selection)
                case .failure(let error):
                    self.onCommentSelectionError?(error.message)
                }
            }
        }

        func showCommentPopover(_ state: CommentPopoverState, in webView: WKWebView) {
            if lastPopoverToken == state.token, commentPopover?.isShown == true {
                return
            }
            closeCommentPopover()

            let deleteHandler: (() -> Void)?
            switch state.mode {
            case .add:
                deleteHandler = nil
            case .edit(let comment):
                deleteHandler = { [weak self] in
                    self?.onDeleteComment?(comment.id)
                    self?.onDismissCommentPopover?()
                }
            }

            let popover = NSPopover()
            popover.behavior = .transient
            popover.delegate = self
            let view = CommentEditorView(
                mode: state.mode,
                onSave: { [weak self] text in
                    guard let self else { return }
                    switch state.mode {
                    case .add(let selection):
                        self.onAddComment?(selection, text)
                    case .edit(let comment):
                        self.onUpdateComment?(comment.id, text)
                    }
                    self.onDismissCommentPopover?()
                },
                onDelete: deleteHandler,
                onCancel: { [weak self] in
                    self?.onDismissCommentPopover?()
                }
            )
            popover.contentViewController = NSHostingController(rootView: view)
            let rect = popoverAnchorRect(state.anchorRect, in: webView)
            popover.show(relativeTo: rect, of: webView, preferredEdge: .maxY)
            commentPopover = popover
            lastPopoverToken = state.token
        }

        func closeCommentPopover() {
            if commentPopover?.isShown == true {
                commentPopover?.close()
            }
            commentPopover = nil
            lastPopoverToken = nil
        }

        func popoverDidClose(_ notification: Notification) {
            onDismissCommentPopover?()
            commentPopover = nil
            lastPopoverToken = nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "commentTapped":
                guard let body = message.body as? [String: Any],
                      let id = body["id"] as? String,
                      let payload = body["payload"] as? String,
                      let rectDict = body["rect"] as? [String: Any],
                      let rect = parseRect(rectDict) else {
                    return
                }
                let decoded = payload.isEmpty ? nil : CommentCodec.decode(json: payload)
                onCommentTapped?(id, rect, decoded)
            case "commentSelection":
                switch parseCommentSelection(message.body) {
                case .success(let selection):
                    onCommentSelection?(selection)
                case .failure(let error):
                    onCommentSelectionError?(error.message)
                }
            default:
                return
            }
        }

        private func parseCommentSelection(_ result: Any?) -> Result<CommentSelection, CommentSelectionError> {
            guard let dict = result as? [String: Any] else {
                return .failure(CommentSelectionError(message: "Select text to add a comment."))
            }
            if let error = dict["error"] as? String, !error.isEmpty {
                return .failure(CommentSelectionError(message: error))
            }
            guard let start = dict["start"] as? Double,
                  let end = dict["end"] as? Double,
                  let text = dict["text"] as? String,
                  let rectDict = dict["rect"] as? [String: Any],
                  let rect = parseRect(rectDict) else {
                return .failure(CommentSelectionError(message: "Selection isn't valid for comments."))
            }
            return .success(CommentSelection(start: Int(start), end: Int(end), text: text, rect: rect))
        }

        private func parseRect(_ dict: [String: Any]) -> CGRect? {
            guard let x = dict["x"] as? Double,
                  let y = dict["y"] as? Double,
                  let width = dict["width"] as? Double,
                  let height = dict["height"] as? Double else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        }

        private func popoverAnchorRect(_ rect: CGRect, in webView: WKWebView) -> CGRect {
            let height = webView.bounds.height
            let adjustedHeight = max(rect.height, 1)
            let adjustedWidth = max(rect.width, 1)
            let y = height - rect.maxY
            return CGRect(x: rect.minX, y: y, width: adjustedWidth, height: adjustedHeight)
        }
    }
}
