import Foundation
import UniformTypeIdentifiers
import WebKit

final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "markv-image"

    private let rootURL: URL
    private let resolvedRootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        self.resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let resolvedFileURL = resolvedFileURL(for: requestURL) else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }

        do {
            let data = try Data(contentsOf: resolvedFileURL)
            let mimeType = UTType(filenameExtension: resolvedFileURL.pathExtension.lowercased())?
                .preferredMIMEType ?? "application/octet-stream"
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    func resolvedFileURL(for requestURL: URL) -> URL? {
        guard requestURL.scheme == Self.scheme else { return nil }
        let encodedPath = requestURL.path.drop(while: { $0 == "/" })
        let relativePath = String(encodedPath).removingPercentEncoding ?? String(encodedPath)
        let fileURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let resolvedFileURL = fileURL.resolvingSymlinksInPath()
        let allowedPrefix = resolvedRootURL.path.hasSuffix("/")
            ? resolvedRootURL.path
            : resolvedRootURL.path + "/"
        guard resolvedFileURL.path.hasPrefix(allowedPrefix) else { return nil }
        return resolvedFileURL
    }
}
