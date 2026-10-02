import AppKit
import Foundation
import Testing
import WebKit
@testable import Markv

private struct FontSizeKeyStore: AIAPIKeyStoring {
    func loadAPIKey() throws -> String { "" }
    func saveAPIKey(_ value: String) throws {}
}

@Test @MainActor func fontSizesPersistAndZoomDoesNotChangeTheDocument() {
    let suite = "MarkvFontSizeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults, restoreLastFolder: false, aiKeyStore: FontSizeKeyStore())

    model.setEditorFontSize(20)
    model.increaseFontSize()
    #expect(model.editorFontSize == 21)
    model.decreaseFontSize()
    model.setSidebarFontSize(16)
    let restored = AppModel(defaults: defaults, restoreLastFolder: false, aiKeyStore: FontSizeKeyStore())
    #expect(restored.editorFontSize == 20)
    #expect(restored.sidebarFontSize == 16)
    #expect(model.documentText.isEmpty)
    #expect(!model.isDirty)

    model.resetEditorFontSize()
    #expect(model.editorFontSize == 17)
    #expect(model.sidebarFontSize == 16)
    model.resetFontSizes()
    #expect(model.sidebarFontSize == 14)
}

@Test @MainActor func fontSizesRejectInvalidValuesAndStopAtBounds() {
    let suite = "MarkvFontSizeBoundsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(100.0, forKey: "markv.editorFontSize")
    defaults.set(-10.0, forKey: "markv.sidebarFontSize")
    let model = AppModel(defaults: defaults, restoreLastFolder: false, aiKeyStore: FontSizeKeyStore())
    #expect(model.editorFontSize == 30)
    #expect(model.sidebarFontSize == 11)
    model.increaseFontSize()
    #expect(model.editorFontSize == 30)
    model.setEditorFontSize(12)
    model.decreaseFontSize()
    #expect(model.editorFontSize == 12)
    model.setEditorFontSize(.nan)
    model.setSidebarFontSize(.infinity)
    #expect(model.editorFontSize == 17)
    #expect(model.sidebarFontSize == 14)
}

@Test @MainActor func fontSizeUpdatesPreserveEditorDraftAndCaretInANarrowWindow() async throws {
    _ = NSApplication.shared
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 500, height: 400), configuration: configuration)
    let coordinator = MarkdownWebView.Coordinator(
        onChange: { _ in }, onPDFExport: { _ in }, onImageImport: { _ in }, onAIEvent: { _ in }
    )
    webView.navigationDelegate = coordinator
    webView.loadHTMLString(MarkdownWebView.documentShell, baseURL: nil)
    for _ in 0..<200 {
        if coordinator.isReady { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    try #require(coordinator.isReady)

    func present(_ fontSize: Double) async {
        let state = MarkdownWebView.Coordinator.NativeState(
            markdown: "Original paragraph", documentID: "test-document", theme: "khaki",
            fontSize: fontSize, focusMode: false, typewriterMode: false,
            language: "en", aiEnabled: false, baseURL: nil
        )
        await withCheckedContinuation { continuation in
            coordinator.apply(state, in: webView) { continuation.resume() }
        }
    }

    func evaluate(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value as? String ?? "") }
            }
        }
    }

    await present(17)
    _ = try await evaluate("""
        window.originalParagraph = document.querySelector('#editor p');
        originalParagraph.firstChild.textContent = 'Unsaved draft';
        const range = document.createRange();
        range.setStart(originalParagraph.firstChild, 3);
        range.collapse(true);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
        'ready';
        """)
    await present(22)
    let result = try await evaluate("""
        JSON.stringify({
          text: document.querySelector('#editor p').textContent,
          sameNode: originalParagraph === document.querySelector('#editor p'),
          caret: window.getSelection().anchorOffset,
          fontSize: getComputedStyle(document.getElementById('editor')).fontSize
        });
        """)
    let values = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    #expect(values["text"] as? String == "Unsaved draft")
    #expect(values["sameNode"] as? Bool == true)
    #expect(values["caret"] as? Int == 3)
    #expect(values["fontSize"] as? String == "22px")
}
