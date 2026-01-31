import Foundation
import WebKit
import UniformTypeIdentifiers

final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "localimage"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let filePath = url.path.removingPercentEncoding,
              !filePath.isEmpty else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = mimeType(for: fileURL)
            let response = URLResponse(url: url, mimeType: mimeType,
                                       expectedContentLength: data.count,
                                       textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No-op for synchronous loading
    }

    private func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}
