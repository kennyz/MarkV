import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
import WebKit
@testable import Markv

@MainActor
private final class EditingHarness {
    let webView: WKWebView
    let coordinator: MarkdownWebView.Coordinator
    let window: NSWindow

    init() {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: MarkdownWebView.shortcutDetectorJavaScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        coordinator = MarkdownWebView.Coordinator(
            onChange: { _ in }, onPDFExport: { _ in }, onImageImport: { _ in }, onAIEvent: { _ in }
        )
        for name in ["editorChanged", "editorEditingBegan", "editorHeadingChanged", "editorModeChanged", "imageImported", "aiEvent"] {
            configuration.userContentController.add(coordinator, name: name)
        }
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 650), configuration: configuration)
        window = NSWindow(contentRect: webView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = webView
        window.makeFirstResponder(webView)
        webView.navigationDelegate = coordinator
    }

    func load(_ markdown: String) async throws {
        if !coordinator.isReady {
            webView.loadHTMLString(MarkdownWebView.documentShell, baseURL: nil)
            for _ in 0..<200 {
                if coordinator.isReady { break }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        try #require(coordinator.isReady)
        let payload = try JSONSerialization.data(withJSONObject: [
            MarkdownRenderer.render(markdown), markdown, "white", false, false, "zh", false, 17
        ] as [Any])
        _ = try await evaluate("markvSetContent(...\(String(decoding: payload, as: UTF8.self))); 'loaded';")
    }

    func evaluate(_ script: String) async throws -> String {
        let result = try await webView.evaluateJavaScript(script)
        return result as? String ?? ""
    }

    func bind(_ model: AppModel) {
        coordinator.onChange = { [weak self, weak model] text in
            guard let self, let model else { return }
            model.updateDocument(text)
            self.apply(model)
        }
        coordinator.onSourceModeChange = { [weak self, weak model] source, text in
            guard let self, let model else { return }
            model.updateEditorMode(source: source, markdown: text)
            self.apply(model)
        }
        apply(model)
    }

    func apply(_ model: AppModel) {
        let state = MarkdownWebView.Coordinator.NativeState(
            markdown: model.documentText, documentID: model.currentFile?.path ?? "mode-test", theme: "white",
            fontSize: model.editorFontSize, focusMode: false, typewriterMode: false,
            language: "zh", aiEnabled: false, baseURL: model.currentFile?.deletingLastPathComponent(),
            sourceMode: model.isSourceMode
        )
        coordinator.pending = state
        coordinator.apply(state, in: webView)
    }

    func waitForJavaScript(_ condition: String) async throws {
        for _ in 0..<100 {
            if try await evaluate("String(\(condition));") == "true" { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await evaluate("String(\(condition));") == "true")
    }

    func snapshot(_ name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["MARKV_EDITING_SNAPSHOTS"] else { return }
        let image = try await webView.takeSnapshot(configuration: nil)
        let representation = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let data = try #require(representation.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name + ".png"))
    }
}

@MainActor
private func withSourceDocument(_ body: (EditingHarness, AppModel, URL) async throws -> Void) async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("source.md")
    let original = "# 标题\n\n正文  \n换行\n\n* 第一项\n* 第二项\n\n"
    try original.write(to: file, atomically: true, encoding: .utf8)
    let suite = "MarkvSourceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults, restoreLastFolder: false)
    model.appLanguage = .chinese
    model.openFile(file)
    let harness = EditingHarness()
    try await harness.load(original)
    harness.bind(model)
    try await body(harness, model, file)
}

@Test @MainActor func sourceModePreservesOriginalMarkdownAndSavesEditsAcrossSwitches() async throws {
    try await withSourceDocument { harness, model, file in
        let original = model.documentText
        harness.coordinator.execute(EditorCommand(action: .toggleSourceMode), in: harness.webView)
        try await harness.waitForJavaScript("!sourceEditor.hidden")
        #expect(model.isSourceMode)
        #expect(try await harness.evaluate("sourceEditor.value;") == original)
        #expect(!model.isDirty)
        #expect(try await harness.evaluate("document.activeElement.id;") == "source")
        _ = try await harness.evaluate("""
            sourceEditor.value = '## 新标题\\n\\n源码编辑 **加粗**\\n';
            sourceEditor.setSelectionRange(5,5);
            sourceEditor.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText'}));
            'done';
            """)
        try await harness.waitForJavaScript("sourceEditor.selectionStart === 5")
        #expect(model.isDirty)
        #expect(model.save())
        #expect(try String(contentsOf: file, encoding: .utf8) == "## 新标题\n\n源码编辑 **加粗**\n")
        try await harness.snapshot("markdown-source")
        harness.coordinator.execute(EditorCommand(action: .toggleSourceMode), in: harness.webView)
        try await harness.waitForJavaScript("!editor.hidden && editor.querySelector('h2')?.textContent === '新标题'")
        #expect(!model.isSourceMode)
        #expect(try await harness.evaluate("editor.querySelector('strong').textContent;") == "加粗")
        #expect(!model.isDirty)
        harness.coordinator.execute(EditorCommand(action: .toggleSourceMode), in: harness.webView)
        try await harness.waitForJavaScript("!sourceEditor.hidden")
        #expect(try await harness.evaluate("sourceEditor.value;") == model.documentText)
        #expect(!model.isDirty)
    }
}

@Test @MainActor func sourceModeFlushesPendingVisualInputAndPreservesSourceCaretOnUpdates() async throws {
    try await withSourceDocument { harness, model, _ in
        _ = try await harness.evaluate("""
            placeCaretAtEnd(editor.querySelector('p'));
            document.execCommand('insertText', false, '刚输入的文字');
            markvCommand('sourceMode', '');
            'done';
            """)
        try await harness.waitForJavaScript("!sourceEditor.hidden && sourceEditor.value.includes('刚输入的文字')")
        _ = try await harness.evaluate("""
            sourceEditor.focus(); sourceEditor.setSelectionRange(0,0);
            document.execCommand('insertText', false, '源码前缀');
            'done';
            """)
        try await harness.waitForJavaScript("sourceEditor.value.startsWith('源码前缀')")
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.documentText.hasPrefix("源码前缀"))
        #expect(model.documentText.contains("刚输入的文字"))
        #expect(try await harness.evaluate("String(sourceEditor.selectionStart);") == "4")
        model.increaseFontSize()
        harness.apply(model)
        try await harness.waitForJavaScript("getComputedStyle(sourceEditor).fontSize === '18px'")
        #expect(try await harness.evaluate("String(sourceEditor.selectionStart);") == "4")
    }
}

@Test @MainActor func sourceModeReloadsCleanExternalChangesAndProtectsDirtySource() async throws {
    try await withSourceDocument { harness, model, file in
        harness.coordinator.execute(EditorCommand(action: .toggleSourceMode), in: harness.webView)
        try await harness.waitForJavaScript("!sourceEditor.hidden")
        try "# 外部更新\n".write(to: file, atomically: true, encoding: .utf8)
        for _ in 0..<100 {
            if model.documentText == "# 外部更新\n" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        harness.apply(model)
        try await harness.waitForJavaScript("sourceEditor.value === '# 外部更新\\n'")
        _ = try await harness.evaluate("sourceEditor.value = '# 未保存的源码'; sourceEditor.dispatchEvent(new InputEvent('input', {bubbles:true})); 'done';")
        try await Task.sleep(for: .milliseconds(50))
        try "# 再次外部更新\n".write(to: file, atomically: true, encoding: .utf8)
        for _ in 0..<100 {
            if model.hasExternalChanges { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.hasExternalChanges)
        #expect(!model.save())
        #expect(model.documentText == "# 未保存的源码")
        #expect(try await harness.evaluate("sourceEditor.value;") == "# 未保存的源码")
    }
}

@Test @MainActor func sourceModePDFExportUsesLatestRenderedContent() async throws {
    try await withSourceDocument { harness, _, file in
        harness.coordinator.execute(EditorCommand(action: .toggleSourceMode), in: harness.webView)
        try await harness.waitForJavaScript("!sourceEditor.hidden")
        _ = try await harness.evaluate("sourceEditor.value = '# Latest source export'; sourceEditor.dispatchEvent(new InputEvent('input', {bubbles:true})); 'done';")
        try await Task.sleep(for: .milliseconds(50))
        let destination = file.deletingLastPathComponent().appendingPathComponent("export.pdf")
        var result: Result<URL, Error>?
        harness.coordinator.onPDFExport = { result = $0 }
        harness.coordinator.execute(EditorCommand(action: .exportPDF(destination)), in: harness.webView)
        for _ in 0..<200 {
            if result != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let exported = try #require(result).get()
        let pdf = try #require(PDFDocument(url: exported))
        #expect(pdf.string?.contains("Latest source export") == true)
        #expect(try await harness.evaluate("String(sourceEditor.hidden);") == "false")
    }
}

@Test @MainActor func sourceModeToolbarSwitchesThroughTheNativeView() async throws {
    try await withSourceDocument { _, model, _ in
        let hosting = NSHostingView(rootView: ContentView().environmentObject(model))
        hosting.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        @MainActor func findWebView(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            for child in view.subviews {
                if let web = findWebView(child) { return web }
            }
            return nil
        }
        var web: WKWebView?
        for _ in 0..<150 {
            web = findWebView(hosting)
            if let web, (try? await web.evaluateJavaScript("typeof markvSetContent")) as? String == "function" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let webView = try #require(web)
        let original = model.documentText
        model.performEditorAction(.toggleSourceMode)
        for _ in 0..<150 {
            if model.isSourceMode, (try? await webView.evaluateJavaScript("!document.getElementById('source').hidden")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.isSourceMode)
        #expect(model.documentText == original)
        #expect(!model.isDirty)
        #expect((try await webView.evaluateJavaScript("document.getElementById('source').getBoundingClientRect().height")) as? Double ?? 0 > 0)
        if let directory = ProcessInfo.processInfo.environment["MARKV_EDITING_SNAPSHOTS"],
           let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(250))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("source-toolbar.png"))
        }
        model.performEditorAction(.toggleSourceMode)
        for _ in 0..<150 {
            if !model.isSourceMode { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!model.isSourceMode)
        #expect(model.documentText == original)
        withExtendedLifetime(window) {}
    }
}

@Test @MainActor func toolbarHeadingLabelTracksCaretAndFormattingWithoutEditingDocument() async throws {
    let harness = EditingHarness()
    let suite = "MarkvHeadingToolbarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults, restoreLastFolder: false)
    model.appLanguage = .chinese
    harness.coordinator.onHeadingLevelChange = { model.updateActiveHeadingLevel($0) }
    let source = "# **一级标题**\n\n## 二级标题\n\n### 三级标题\n\n#### 四级标题\n\n##### 五级标题\n\n###### 六级标题\n\n正文\n\n- 列表"
    try await harness.load(source)

    func waitForLevel(_ level: Int?) async throws {
        for _ in 0..<100 {
            if model.activeHeadingLevel == level { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.activeHeadingLevel == level)
    }

    for level in 1...6 {
        let target = level == 1 ? "h1 strong" : "h\(level)"
        _ = try await harness.evaluate("placeCaretAtEnd(editor.querySelector('\(target)')); 'done';")
        try await waitForLevel(level)
        #expect(model.editorBlockTitle == "标题 \(level)")
    }
    _ = try await harness.evaluate("placeCaretAtEnd(editor.querySelector('p')); 'done';")
    try await waitForLevel(nil)
    #expect(model.editorBlockTitle == "正文")
    #expect(!model.isDirty)
    #expect(model.documentText.isEmpty)

    _ = try await harness.evaluate("markvCommand('block', 'h2'); 'done';")
    try await waitForLevel(2)
    #expect(model.editorBlockTitle == "标题 2")
    _ = try await harness.evaluate("markvCommand('block', 'p'); 'done';")
    try await waitForLevel(nil)

    _ = try await harness.evaluate("placeCaretAtEnd(editor.querySelector('li')); 'done';")
    try await waitForLevel(nil)
    #expect(model.editorBlockTitle == "正文")
    // Replacing the document must not leave the previous heading in the toolbar.
    _ = try await harness.evaluate("placeCaretAtEnd(editor.querySelector('h3')); 'done';")
    try await waitForLevel(3)
    try await harness.load("新文档")
    try await waitForLevel(nil)
}

@Test @MainActor func mergingHeadingBlocksKeepsOneConsistentFontSize() async throws {
    let harness = EditingHarness()
    try await harness.load("### 【候选人】\n\n# - 运营 - 实习生 - 岗位评价\n\n- 整体素质不错，潜力较好")
    let result = try await harness.evaluate("""
        const heading = editor.querySelector('h1');
        const range = document.createRange();
        range.setStart(heading.firstChild, 0);
        range.collapse(true);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
        editor.focus();
        document.execCommand('delete');
        const merged = editor.querySelector('h3');
        JSON.stringify({html: editor.innerHTML, sizes: [getComputedStyle(merged).fontSize,
          ...Array.from(merged.querySelectorAll('*')).map(node => getComputedStyle(node).fontSize)]});
        """)
    let values = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    let sizes = try #require(values["sizes"] as? [String])
    #expect(Set(sizes).count == 1)
    try await harness.snapshot("merged-heading")
}

@Test @MainActor func pastedRichTextUsesDocumentFontsAndKeepsSemanticFormatting() async throws {
    let harness = EditingHarness()
    try await harness.load("# 招聘评价\n\n正文")
    let result = try await harness.evaluate("""
        placeCaretAtEnd(editor.querySelector('p'));
        const clipboard = new DataTransfer();
        clipboard.setData('text/plain', '候选人评价');
        clipboard.setData('text/html', '<span style="font-family:Arial;font-size:48px;color:red"><b>候选人</b>评价</span>');
        const paste = new ClipboardEvent('paste', {bubbles:true, cancelable:true, clipboardData:clipboard});
        editor.dispatchEvent(paste);
        if (!paste.defaultPrevented) document.execCommand('insertHTML', false, clipboard.getData('text/html'));
        JSON.stringify({html: editor.innerHTML, markdown: toMarkdown(), styled: editor.querySelectorAll('[style]').length});
        """)
    let values = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    #expect(values["styled"] as? Int == 0)
    #expect((values["markdown"] as? String)?.contains("**候选人**评价") == true)
    try await harness.snapshot("rich-paste")
}

@Test @MainActor func convertingHeadingToParagraphResetsSizeAndPreservesBold() async throws {
    let harness = EditingHarness()
    try await harness.load("# **候选人** - 运营实习生")
    _ = try await harness.evaluate("placeCaretAtEnd(editor.querySelector('h1')); markvCommand('block', 'p'); 'done';")
    let result = try await harness.evaluate("""
        JSON.stringify({markdown:toMarkdown(), sizes:Array.from(editor.querySelectorAll('p,p *')).map(node => getComputedStyle(node).fontSize)});
        """)
    let values = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    #expect(values["markdown"] as? String == "**候选人** - 运营实习生\n")
    #expect(Set(values["sizes"] as? [String] ?? []) == ["17px"])
}

@Test @MainActor func headingEnterAndTypingKeepNewParagraphAtBodySize() async throws {
    let harness = EditingHarness()
    try await harness.load("# 候选人评价")
    let result = try await harness.evaluate("""
        placeCaretAtEnd(editor.querySelector('h1'));
        document.execCommand('insertParagraph');
        document.execCommand('insertText', false, '整体素质不错，潜力较好');
        JSON.stringify({html:editor.innerHTML, markdown:toMarkdown()});
        """)
    let values = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    #expect(values["markdown"] as? String == "# 候选人评价\n\n整体素质不错，潜力较好\n")
}

@Test @MainActor func boldAndItalicSurviveEditingAndReload() async throws {
    let harness = EditingHarness()
    try await harness.load("候选人评价")
    _ = try await harness.evaluate("""
        const range = document.createRange();
        range.setStart(editor.querySelector('p').firstChild, 0);
        range.setEnd(editor.querySelector('p').firstChild, 3);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
        markvCommand('bold', '');
        markvCommand('italic', '');
        'done';
        """)
    let markdown = try await harness.evaluate("toMarkdown();")
    try await harness.load(markdown)
    #expect(try await harness.evaluate("editor.querySelector('strong em, em strong')?.textContent || ''; ") == "候选人")
    #expect(try await harness.evaluate("editor.querySelector('p').innerHTML;") == "<strong><em>候选人</em></strong>评价")
}

@Test @MainActor func undoRedoAfterMergingBlocksPreservesTextAndTypography() async throws {
    let harness = EditingHarness()
    try await harness.load("### 姓名\n\n# 岗位")
    _ = try await harness.evaluate("""
        const range = document.createRange(); range.setStart(editor.querySelector('h1').firstChild, 0); range.collapse(true);
        window.getSelection().removeAllRanges(); window.getSelection().addRange(range); editor.focus();
        document.execCommand('delete');
        'done';
        """)
    try await Task.sleep(for: .milliseconds(200))
    _ = try await harness.evaluate("document.execCommand('insertText', false, '评价'); 'done';")
    #expect(try await harness.evaluate("String(window.getSelection().anchorNode.textContent.includes('评价'));") == "true")
    _ = try await harness.evaluate("document.execCommand('undo'); 'done';")
    #expect(try await harness.evaluate("editor.textContent.replace(/\\s/g,'');") == "姓名岗位")
    #expect(try await harness.evaluate("String(editor.querySelectorAll('h1,h3').length);") == "2")
    _ = try await harness.evaluate("document.execCommand('redo'); 'done';")
    #expect(try await harness.evaluate("editor.textContent.replace(/\\s/g,'');") == "姓名评价岗位")
    #expect(try await harness.evaluate("String(editor.querySelectorAll('h1,h3').length);") == "1")
    #expect(try await harness.evaluate("String(new Set(Array.from(editor.querySelectorAll('h3,h3 *')).map(node => getComputedStyle(node).fontSize)).size);") == "1")
}

@Test @MainActor func chineseCompositionDoesNotConvertOrReplaceTextMidInput() async throws {
    let harness = EditingHarness()
    try await harness.load("正文")
    let result = try await harness.evaluate("""
        const paragraph = editor.querySelector('p'); placeCaretAtEnd(paragraph);
        editor.dispatchEvent(new CompositionEvent('compositionstart', {bubbles:true}));
        paragraph.textContent = '# ';
        editor.dispatchEvent(new InputEvent('input', {bubbles:true, isComposing:true, inputType:'insertCompositionText'}));
        const intact = paragraph === editor.querySelector('p');
        paragraph.textContent = '# 候选人评价'; placeCaretAtEnd(paragraph);
        editor.dispatchEvent(new CompositionEvent('compositionend', {bubbles:true, data:'候选人评价'}));
        JSON.stringify({intact, text:paragraph.textContent, connected:paragraph.isConnected, caret:window.getSelection().anchorOffset});
        """)
    let values = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    #expect(values["intact"] as? Bool == true)
    #expect(values["connected"] as? Bool == true)
    #expect(values["text"] as? String == "# 候选人评价")
    #expect(values["caret"] as? Int == 1)
}

@Test @MainActor func pastedCSSFormattingSurvivesSaveAndReloadWithoutForeignFonts() async throws {
    let harness = EditingHarness()
    try await harness.load("正文：")
    _ = try await harness.evaluate("""
        placeCaretAtEnd(editor.querySelector('p'));
        const clipboard = new DataTransfer();
        clipboard.setData('text/html', '<span style="font-size:40px;font-weight:700;font-style:italic">评价</span>');
        editor.dispatchEvent(new ClipboardEvent('paste', {bubbles:true, cancelable:true, clipboardData:clipboard}));
        'done';
        """)
    let markdown = try await harness.evaluate("toMarkdown();")
    try await harness.load(markdown)
    #expect(try await harness.evaluate("editor.querySelector('strong em,em strong')?.textContent || '';") == "评价")
    #expect(try await harness.evaluate("String(editor.querySelectorAll('[style]').length);") == "0")
}

@Test @MainActor func plainTextPastePreservesMultipleParagraphs() async throws {
    let harness = EditingHarness()
    try await harness.load("")
    _ = try await harness.evaluate("""
        placeCaretAtEnd(editor.querySelector('p'));
        const clipboard = new DataTransfer(); clipboard.setData('text/plain', '第一段\\n\\n第二段');
        editor.dispatchEvent(new ClipboardEvent('paste', {bubbles:true, cancelable:true, clipboardData:clipboard}));
        'done';
        """)
    let markdown = try await harness.evaluate("toMarkdown();")
    #expect(markdown.contains("第一段\n\n第二段"))
    try await harness.load(markdown)
    #expect(try await harness.evaluate("String(editor.querySelectorAll('p').length);") == "2")
}

@Test @MainActor func editingCodeBlockPreservesInsertedLineBreaksOnReload() async throws {
    let harness = EditingHarness()
    try await harness.load("```swift\nlet a = 1\n```")
    _ = try await harness.evaluate("""
        placeCaretAtEnd(editor.querySelector('code'));
        document.execCommand('insertLineBreak'); document.execCommand('insertText', false, 'let b = 2');
        'done';
        """)
    let markdown = try await harness.evaluate("toMarkdown();")
    #expect(markdown.contains("let a = 1\nlet b = 2"))
    try await harness.load(markdown)
    #expect(try await harness.evaluate("editor.querySelector('code').textContent;") == "let a = 1\nlet b = 2")
}

@Test @MainActor func pastedBlockContainersKeepParagraphsAndListsOnReload() async throws {
    let harness = EditingHarness()
    try await harness.load("")
    _ = try await harness.evaluate("""
        placeCaretAtEnd(editor.querySelector('p'));
        const clipboard = new DataTransfer();
        clipboard.setData('text/html', '<div><p>第一段</p><p>第二段</p><ul><li>沟通能力</li><li>文字能力</li></ul></div>');
        editor.dispatchEvent(new ClipboardEvent('paste', {bubbles:true, cancelable:true, clipboardData:clipboard}));
        'done';
        """)
    let markdown = try await harness.evaluate("toMarkdown();")
    #expect(markdown.contains("第一段\n\n第二段"))
    #expect(markdown.contains("- 沟通能力\n- 文字能力"))
    try await harness.load(markdown)
    #expect(try await harness.evaluate("String(editor.querySelectorAll('li').length);") == "2")
}

@Test @MainActor func orderedAndTaskListNestingPreservesHierarchyAndStartNumber() async throws {
    let harness = EditingHarness()
    let source = "3. 招聘\n   - [x] 沟通能力\n     - 表达清楚\n   - [ ] 文字能力\n4. 下一步"
    try await harness.load(source)
    #expect(try await harness.evaluate("editor.querySelector('ol').getAttribute('start');") == "3")
    #expect(try await harness.evaluate("String(editor.querySelectorAll('li > ul').length);") == "2")
    #expect(try await harness.evaluate("String(editor.querySelectorAll('input:checked').length);") == "1")
    let markdown = try await harness.evaluate("toMarkdown();")
    #expect(markdown.hasPrefix("3. 招聘\n   - [x] 沟通能力\n     - 表达清楚"))
    try await harness.load(markdown)
    #expect(try await harness.evaluate("String(editor.querySelectorAll('li > ul').length);") == "2")
}

@Test @MainActor func nestedListsSurviveSaveAndReload() async throws {
    let harness = EditingHarness()
    try await harness.load("- 综合评价\n  - 沟通能力\n  - 文字能力\n- 下一步")
    #expect(try await harness.evaluate("String(editor.querySelectorAll('li > ul').length);") == "1")
    let markdown = try await harness.evaluate("toMarkdown();")
    try await harness.load(markdown)
    #expect(try await harness.evaluate("String(editor.querySelectorAll('li > ul').length);") == "1")
}
