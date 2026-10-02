import Foundation
import Testing
@testable import Markv

@Test func securityScopedBookmarksRestoreRefreshAndBalanceAccess() throws {
    let suite = "MarkvBookmarksTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let requested = URL(fileURLWithPath: "/tmp/selected-folder")
    let moved = URL(fileURLWithPath: "/tmp/moved-folder")
    var starts: [URL] = []
    var stops: [URL] = []
    var writes: [URL] = []
    var access: SecurityScopedFileAccess? = SecurityScopedFileAccess(
        defaults: defaults,
        makeBookmark: { writes.append($0); return Data("bookmark".utf8) },
        resolveBookmark: { _ in (moved, true) },
        startAccess: { starts.append($0); return true },
        stopAccess: { stops.append($0) })
    #expect(access?.access(requested, remember: true) == requested)
    #expect(access?.access(requested) == requested)
    #expect(starts == [requested])
    access = nil
    #expect(stops == [requested])
    access = SecurityScopedFileAccess(
        defaults: defaults,
        makeBookmark: { writes.append($0); return Data("renewed".utf8) },
        resolveBookmark: { _ in (moved, true) },
        startAccess: { starts.append($0); return true },
        stopAccess: { stops.append($0) })
    #expect(access?.access(requested) == moved)
    #expect(writes == [requested, moved])
    #expect((defaults.dictionary(forKey: "markv.securityScopedBookmarks") as? [String: Data])?[moved.path] == Data("renewed".utf8))
    access = nil
    #expect(stops == [requested, moved])
}

@Test func activeScopeCanBeRememberedAfterInitialAccess() {
    let suite = "MarkvLateBookmarkTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let url = URL(fileURLWithPath: "/tmp/selected-later.md")
    var starts = 0
    let access = SecurityScopedFileAccess(defaults: defaults,
        makeBookmark: { _ in Data("saved".utf8) },
        startAccess: { _ in starts += 1; return true })
    #expect(access.access(url) == url)
    #expect(access.access(url, remember: true) == url)
    #expect(starts == 1)
    #expect((defaults.dictionary(forKey: "markv.securityScopedBookmarks") as? [String: Data])?[url.path] == Data("saved".utf8))
}

@Test func invalidBookmarkAndDeniedScopeDoNotInventAccess() {
    let suite = "MarkvDeniedBookmarksTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let url = URL(fileURLWithPath: "/tmp/selected-file.md")
    defaults.set([url.path: Data("invalid".utf8)], forKey: "markv.securityScopedBookmarks")
    var stops = 0
    var access: SecurityScopedFileAccess? = SecurityScopedFileAccess(
        defaults: defaults,
        makeBookmark: { _ in throw CocoaError(.fileReadNoPermission) },
        resolveBookmark: { _ in throw CocoaError(.fileReadCorruptFile) },
        startAccess: { _ in false },
        stopAccess: { _ in stops += 1 })
    #expect(access?.access(url, remember: true) == url)
    access = nil
    #expect(stops == 0)
}
