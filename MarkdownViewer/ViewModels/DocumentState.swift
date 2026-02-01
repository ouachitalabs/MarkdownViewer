import Combine
import CoreGraphics
import Foundation
import Markdown

class DocumentState: ObservableObject {
    private static let zoomLevelKey = "zoomLevel"
    private static let contentWidthKey = "contentWidth"
    static let zoomChangedNotification = Notification.Name("DocumentStateZoomChanged")
    static let contentWidthChangedNotification = Notification.Name("DocumentStateContentWidthChanged")

    @Published var htmlContent: String = ""
    @Published var title: String = "Markdown Viewer"
    @Published var fileChanged: Bool = false
    @Published var outlineItems: [OutlineItem] = []
    @Published var reloadToken: UUID?
    @Published var zoomLevel: CGFloat {
        didSet {
            guard !isSyncingZoom else { return }
            UserDefaults.standard.set(zoomLevel, forKey: Self.zoomLevelKey)
            NotificationCenter.default.post(
                name: Self.zoomChangedNotification,
                object: self,
                userInfo: ["zoomLevel": zoomLevel]
            )
        }
    }
    private var isSyncingZoom = false

    @Published var contentWidth: CGFloat {
        didSet {
            guard !isSyncingWidth else { return }
            UserDefaults.standard.set(contentWidth, forKey: Self.contentWidthKey)
            NotificationCenter.default.post(
                name: Self.contentWidthChangedNotification,
                object: self,
                userInfo: ["contentWidth": contentWidth]
            )
        }
    }
    private var isSyncingWidth = false
    @Published var isShowingFindBar: Bool = false
    @Published var findQuery: String = ""
    @Published var findRequest: FindRequest?
    @Published var findFocusToken: UUID = UUID()
    var currentURL: URL?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var lastModificationDate: Date?
    private let recentFilesStore: RecentFilesStore
    private var zoomObserver: Any?
    private var widthObserver: Any?

    init(recentFilesStore: RecentFilesStore = .shared) {
        self.recentFilesStore = recentFilesStore
        let storedZoom = UserDefaults.standard.double(forKey: Self.zoomLevelKey)
        self.zoomLevel = storedZoom > 0 ? CGFloat(storedZoom) : 1.0

        let storedWidth = UserDefaults.standard.double(forKey: Self.contentWidthKey)
        self.contentWidth = storedWidth > 0 ? CGFloat(storedWidth) : 980

        zoomObserver = NotificationCenter.default.addObserver(
            forName: Self.zoomChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  notification.object as? DocumentState !== self,
                  let newZoom = notification.userInfo?["zoomLevel"] as? CGFloat else { return }
            self.isSyncingZoom = true
            self.zoomLevel = newZoom
            self.isSyncingZoom = false
        }

        widthObserver = NotificationCenter.default.addObserver(
            forName: Self.contentWidthChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  notification.object as? DocumentState !== self,
                  let newWidth = notification.userInfo?["contentWidth"] as? CGFloat else { return }
            self.isSyncingWidth = true
            self.contentWidth = newWidth
            self.isSyncingWidth = false
        }
    }

    deinit {
        stopMonitoring()
        if let zoomObserver {
            NotificationCenter.default.removeObserver(zoomObserver)
        }
        if let widthObserver {
            NotificationCenter.default.removeObserver(widthObserver)
        }
    }

    func loadFile(at url: URL) {
        currentURL = url
        fileChanged = false
        startMonitoring(url: url)
        recentFilesStore.add(url)
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let (frontMatter, content) = MarkdownDocumentParser.parseFrontMatter(markdown)
            let document = Document(parsing: content)
            var renderer = MarkdownRenderer()
            let rendered = renderer.render(document, baseURL: url.deletingLastPathComponent())
            let frontMatterHTML = renderFrontMatter(frontMatter)
            htmlContent = wrapInHTML(frontMatterHTML + rendered.html, title: url.lastPathComponent)
            title = url.lastPathComponent
            outlineItems = MarkdownDocumentParser.normalizedOutline(rendered.outline)
        } catch {
            htmlContent = wrapInHTML("<p>Error loading file: \(error.localizedDescription)</p>", title: "Error")
            title = "Error"
            outlineItems = []
        }
    }

    private func renderFrontMatter(_ frontMatter: [(String, String)]) -> String {
        guard !frontMatter.isEmpty else { return "" }

        var html = """
        <div class=\"front-matter\">
        <table class=\"front-matter-table\">
        """
        for (key, value) in frontMatter {
            let displayKey = key.replacingOccurrences(of: "_", with: " ").capitalized
            html += "<tr><td class=\"fm-key\">\(escapeHTML(displayKey))</td><td class=\"fm-value\">\(escapeHTML(value))</td></tr>\n"
        }
        html += "</table></div>\n"
        return html
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
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

    func increaseContentWidth() {
        contentWidth = min(contentWidth + 100, 2000)
    }

    func decreaseContentWidth() {
        contentWidth = max(contentWidth - 100, 500)
    }

    func resetContentWidth() {
        contentWidth = 980
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
        MarkdownHTMLTemplate.shared.render(body: body, title: title)
    }
}
