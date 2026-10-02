import Foundation

/// Retains access only to URLs explicitly selected by the user or restored from their bookmarks.
final class SecurityScopedFileAccess {
    private let defaults: UserDefaults
    private let key = "markv.securityScopedBookmarks"
    private var activeURLs: [String: URL] = [:]
    private let makeBookmark: (URL) throws -> Data
    private let resolveBookmark: (Data) throws -> (URL, Bool)
    private let startAccess: (URL) -> Bool
    private let stopAccess: (URL) -> Void

    init(defaults: UserDefaults,
         makeBookmark: @escaping (URL) throws -> Data = {
             try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
         },
         resolveBookmark: @escaping (Data) throws -> (URL, Bool) = { data in
             var stale = false
             let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
             return (url, stale)
         },
         startAccess: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stopAccess: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.defaults = defaults
        self.makeBookmark = makeBookmark
        self.resolveBookmark = resolveBookmark
        self.startAccess = startAccess
        self.stopAccess = stopAccess
    }

    func access(_ requestedURL: URL, remember: Bool = false) -> URL {
        let path = requestedURL.standardizedFileURL.path
        var bookmarks = defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
        if let active = activeURLs[path] {
            if remember, let data = try? makeBookmark(active) {
                bookmarks[path] = data
                bookmarks[active.standardizedFileURL.path] = data
                defaults.set(bookmarks, forKey: key)
            }
            return active
        }
        var url = requestedURL
        var stale = false
        if let data = bookmarks[path], let resolved = try? resolveBookmark(data) {
            url = resolved.0
            stale = resolved.1
        }
        if startAccess(url) { activeURLs[path] = url }
        if remember || stale, let data = try? makeBookmark(url) {
            bookmarks[path] = data
            bookmarks[url.standardizedFileURL.path] = data
            defaults.set(bookmarks, forKey: key)
        }
        return url
    }

    deinit {
        for url in activeURLs.values { stopAccess(url) }
    }
}
