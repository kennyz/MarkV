import AppKit
import SwiftUI
import WebKit

enum PDFExportError: LocalizedError {
    case failed

    var errorDescription: String? {
        "The print operation did not create a PDF file."
    }
}

enum EditorAction: Equatable {
    case paragraph
    case heading(Int)
    case bold
    case italic
    case strike
    case inlineCode
    case codeBlock
    case quote
    case unorderedList
    case orderedList
    case taskList
    case link
    case image
    case insertImage(String)
    case captureAISelection
    case replaceAISelection(String)
    case insertAfterAISelection(String)
    case replaceAISlashHTML(String)
    case clearAIContext
    case table
    case horizontalRule
    case jumpToHeading(String)
    case focusEditor
    case exportPDF(URL)
}

struct EditorCommand: Identifiable, Equatable {
    let id = UUID()
    let action: EditorAction
}

struct EditorImagePayload: Equatable {
    let data: Data
    let suggestedFilename: String?
    let mimeType: String?
}

enum EditorAIEvent: Equatable {
    case selection(String)
    case slash
}

@MainActor
enum MarkvPDFExporter {
    private static let a4Page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    private static let pageMargin: CGFloat = 42

    static func export(
        _ webView: WKWebView,
        to destination: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task { @MainActor in
            do {
                _ = try await webView.evaluateJavaScript(
                    "document.body.classList.add('pdf-export'); true"
                )
                let dimensions = try await pageDimensions(in: webView)
                let configuration = WKPDFConfiguration()
                configuration.rect = CGRect(origin: .zero, size: dimensions)
                configuration.allowTransparentBackground = false
                let sourceData = try await webView.pdf(configuration: configuration)
                _ = try? await webView.evaluateJavaScript(
                    "document.body.classList.remove('pdf-export'); true"
                )

                let paginated = try paginate(sourceData)
                try paginated.write(to: destination, options: .atomic)
                completion(.success(destination))
            } catch {
                _ = try? await webView.evaluateJavaScript(
                    "document.body.classList.remove('pdf-export'); true"
                )
                completion(.failure(error))
            }
        }
    }

    private static func pageDimensions(in webView: WKWebView) async throws -> CGSize {
        let result = try await webView.evaluateJavaScript(
            """
            ({
              width: Math.max(document.documentElement.scrollWidth, document.body.scrollWidth),
              height: Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)
            })
            """
        )
        guard let values = result as? [String: Any],
              let width = (values["width"] as? NSNumber)?.doubleValue,
              let height = (values["height"] as? NSNumber)?.doubleValue,
              width > 0,
              height > 0 else {
            throw PDFExportError.failed
        }
        return CGSize(width: width, height: height)
    }

    static func paginate(_ sourceData: Data) throws -> Data {
        guard let provider = CGDataProvider(data: sourceData as CFData),
              let sourceDocument = CGPDFDocument(provider),
              sourceDocument.numberOfPages > 0 else {
            throw PDFExportError.failed
        }

        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw PDFExportError.failed
        }
        var pageBox = a4Page
        guard let context = CGContext(consumer: consumer, mediaBox: &pageBox, nil) else {
            throw PDFExportError.failed
        }

        let printable = a4Page.insetBy(dx: pageMargin, dy: pageMargin)
        for pageNumber in 1...sourceDocument.numberOfPages {
            guard let sourcePage = sourceDocument.page(at: pageNumber) else { continue }
            let sourceBox = sourcePage.getBoxRect(.mediaBox)
            guard sourceBox.width > 0, sourceBox.height > 0 else { continue }

            let scale = printable.width / sourceBox.width
            let sourceSliceHeight = printable.height / scale
            let sliceCount = max(1, Int(ceil(sourceBox.height / sourceSliceHeight)))

            for sliceIndex in 0..<sliceCount {
                let sourceUpperY = sourceBox.maxY - (CGFloat(sliceIndex) * sourceSliceHeight)
                let xOffset = printable.minX - (sourceBox.minX * scale)
                let yOffset = printable.maxY - (sourceUpperY * scale)

                context.beginPDFPage(nil)
                context.saveGState()
                context.clip(to: printable)
                context.concatenate(CGAffineTransform(
                    a: scale,
                    b: 0,
                    c: 0,
                    d: scale,
                    tx: xOffset,
                    ty: yOffset
                ))
                context.drawPDFPage(sourcePage)
                context.restoreGState()
                context.endPDFPage()
            }
        }

        context.closePDF()
        guard output.length > 0 else { throw PDFExportError.failed }
        return output as Data
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let documentID: String
    let theme: AppearanceTheme
    let fontSize: Double
    let baseURL: URL?
    let focusMode: Bool
    let typewriterMode: Bool
    let language: AppLanguage
    let aiEnabled: Bool
    let command: EditorCommand?
    let onChange: (String) -> Void
    let onPDFExport: (Result<URL, Error>) -> Void
    let onImageImport: (EditorImagePayload) -> Void
    let onAIEvent: (EditorAIEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onChange: onChange,
            onPDFExport: onPDFExport,
            onImageImport: onImageImport,
            onAIEvent: onAIEvent
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if let baseURL {
            configuration.setURLSchemeHandler(
                LocalImageSchemeHandler(rootURL: baseURL),
                forURLScheme: LocalImageSchemeHandler.scheme
            )
        }
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.shortcutDetectorJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController.add(context.coordinator, name: "editorChanged")
        configuration.userContentController.add(context.coordinator, name: "imageImported")
        configuration.userContentController.add(context.coordinator, name: "aiEvent")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.documentShell, baseURL: baseURL)
        context.coordinator.pending = .init(
            markdown: markdown,
            documentID: documentID,
            theme: theme.rawValue,
            fontSize: fontSize,
            focusMode: focusMode,
            typewriterMode: typewriterMode,
            language: language.rawValue,
            aiEnabled: aiEnabled,
            baseURL: baseURL
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onPDFExport = onPDFExport
        context.coordinator.onImageImport = onImageImport
        context.coordinator.onAIEvent = onAIEvent
        let state = Coordinator.NativeState(
            markdown: markdown,
            documentID: documentID,
            theme: theme.rawValue,
            fontSize: fontSize,
            focusMode: focusMode,
            typewriterMode: typewriterMode,
            language: language.rawValue,
            aiEnabled: aiEnabled,
            baseURL: baseURL
        )
        context.coordinator.pending = state

        guard context.coordinator.isReady else { return }
        context.coordinator.apply(state, in: webView) {
            context.coordinator.execute(command, in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "editorChanged")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageImported")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "aiEvent")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        struct NativeState {
            let markdown: String
            let documentID: String
            let theme: String
            let fontSize: Double
            let focusMode: Bool
            let typewriterMode: Bool
            let language: String
            let aiEnabled: Bool
            let baseURL: URL?
        }

        var isReady = false
        var pending: NativeState?
        var onChange: (String) -> Void
        var onPDFExport: (Result<URL, Error>) -> Void
        var onImageImport: (EditorImagePayload) -> Void
        var onAIEvent: (EditorAIEvent) -> Void
        private var lastWebMarkdown: String?
        private var lastNativeMarkdown: String?
        private var lastDocumentID = ""
        private var lastCommandID: UUID?

        init(
            onChange: @escaping (String) -> Void,
            onPDFExport: @escaping (Result<URL, Error>) -> Void,
            onImageImport: @escaping (EditorImagePayload) -> Void,
            onAIEvent: @escaping (EditorAIEvent) -> Void
        ) {
            self.onChange = onChange
            self.onPDFExport = onPDFExport
            self.onImageImport = onImageImport
            self.onAIEvent = onAIEvent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let pending {
                apply(pending, in: webView, force: true)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "editorChanged", let markdown = message.body as? String {
                lastWebMarkdown = markdown
                onChange(markdown)
                return
            }
            if handleAIMessage(message) { return }

            guard message.name == "imageImported",
                  let values = message.body as? [String: Any] else { return }
            if values["error"] as? String == "tooLarge" {
                let language = AppLanguage(rawValue: pending?.language ?? "") ?? .english
                let alert = NSAlert()
                alert.messageText = language.text("Images larger than 25 MB are not supported.")
                alert.addButton(withTitle: language.text("OK"))
                alert.runModal()
                return
            }
            if let payload = MarkdownWebView.imagePayload(from: values) {
                onImageImport(payload)
            }
            return
        }

        private func handleAIMessage(_ message: WKScriptMessage) -> Bool {
            guard message.name == "aiEvent",
                  let values = message.body as? [String: Any],
                  let type = values["type"] as? String else { return false }
            switch type {
            case "selection":
                onAIEvent(.selection(values["text"] as? String ?? ""))
            case "slash":
                onAIEvent(.slash)
            default:
                break
            }
            return true
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor (String?) -> Void
        ) {
            let alert = NSAlert()
            let language = AppLanguage(rawValue: pending?.language ?? "") ?? .english
            alert.messageText = prompt
            alert.addButton(withTitle: language.text("Insert"))
            alert.addButton(withTitle: language.text("Cancel"))
            let field = NSTextField(string: defaultText ?? "https://")
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = field
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
        }

        func apply(
            _ state: NativeState,
            in webView: WKWebView,
            force: Bool = false,
            completion: (() -> Void)? = nil
        ) {
            let documentChanged = state.documentID != lastDocumentID
            let originatedOutsideEditor = state.markdown != lastWebMarkdown && state.markdown != lastNativeMarkdown

            if force || documentChanged || originatedOutsideEditor {
                let html = MarkdownRenderer.render(
                    state.markdown,
                    localImageBaseURL: state.baseURL
                )
                guard let payload = json([html, state.markdown, state.theme, state.focusMode, state.typewriterMode, state.language, state.aiEnabled, state.fontSize]) else { return }
                webView.evaluateJavaScript("window.markvSetContent(...\(payload))") { _, _ in
                    completion?()
                }
                lastNativeMarkdown = state.markdown
                lastWebMarkdown = nil
                lastDocumentID = state.documentID
            } else if let payload = json([state.theme, state.focusMode, state.typewriterMode, state.language, state.aiEnabled, state.fontSize]) {
                webView.evaluateJavaScript("window.markvSetPresentation(...\(payload))") { _, _ in
                    completion?()
                }
            }
        }

        func execute(_ command: EditorCommand?, in webView: WKWebView) {
            guard let command, command.id != lastCommandID else { return }
            lastCommandID = command.id

            if case .exportPDF(let destination) = command.action {
                exportPDF(from: webView, to: destination)
                return
            }

            let name: String
            let value: Any
            switch command.action {
            case .paragraph: (name, value) = ("block", "p")
            case .heading(let level): (name, value) = ("block", "h\(min(max(level, 1), 6))")
            case .bold: (name, value) = ("bold", "")
            case .italic: (name, value) = ("italic", "")
            case .strike: (name, value) = ("strike", "")
            case .inlineCode: (name, value) = ("inlineCode", "")
            case .codeBlock: (name, value) = ("block", "pre")
            case .quote: (name, value) = ("block", "blockquote")
            case .unorderedList: (name, value) = ("unorderedList", "")
            case .orderedList: (name, value) = ("orderedList", "")
            case .taskList: (name, value) = ("taskList", "")
            case .link: (name, value) = ("link", "")
            case .image: (name, value) = ("image", "")
            case .insertImage(let path): (name, value) = ("insertImage", path)
            case .captureAISelection: (name, value) = ("captureAISelection", "")
            case .replaceAISelection(let text): (name, value) = ("replaceAISelection", text)
            case .insertAfterAISelection(let text): (name, value) = ("insertAfterAISelection", text)
            case .replaceAISlashHTML(let html): (name, value) = ("replaceAISlashHTML", html)
            case .clearAIContext: (name, value) = ("clearAIContext", "")
            case .table: (name, value) = ("table", "")
            case .horizontalRule: (name, value) = ("horizontalRule", "")
            case .jumpToHeading(let anchor): (name, value) = ("jump", anchor)
            case .focusEditor: (name, value) = ("focus", "")
            case .exportPDF: return
            }
            guard let payload = json([name, value]) else { return }
            webView.evaluateJavaScript("window.markvCommand(...\(payload))")
        }

        private func exportPDF(from webView: WKWebView, to destination: URL) {
            MarkvPDFExporter.export(webView, to: destination, completion: onPDFExport)
        }

        private func json(_ value: Any) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    static let shortcutDetectorJavaScript = #"""
    globalThis.markvNormalizeShortcutText = function(value) {
      return String(value || '')
        .replace(/[\u200B\u2060\uFEFF]/g, '')
        .replace(/[\u00A0\u202F]/g, ' ')
        .replace(/[\r\n]/g, '');
    };

    globalThis.markvDetectShortcut = function(value) {
      const text = globalThis.markvNormalizeShortcutText(value);
      const heading = text.match(/^(#{1,6}) $/);
      if (heading) return {type:'heading', level:heading[1].length};
      if (/^- \[[ xX]\] $/.test(text)) return {type:'task', checked:/[xX]/.test(text)};
      if (/^> $/.test(text)) return {type:'quote'};
      if (/^[-*+] $/.test(text)) return {type:'unordered'};
      if (/^1\. $/.test(text)) return {type:'ordered'};
      const fence = text.trim().match(/^(```|~~~)([\w+-]*)$/);
      if (fence) return {type:'code', language:fence[2] || ''};
      return null;
    };

    globalThis.markvDetectTaskItem = function(value) {
      const text = globalThis.markvNormalizeShortcutText(value);
      if (/^\[[ xX]\] $/.test(text)) return {checked:/[xX]/.test(text)};
      return null;
    };
    """#

    static func imagePayload(from values: [String: Any]) -> EditorImagePayload? {
        guard let base64 = values["base64"] as? String,
              let data = Data(base64Encoded: base64) else { return nil }
        return EditorImagePayload(
            data: data,
            suggestedFilename: values["name"] as? String,
            mimeType: values["mimeType"] as? String
        )
    }

    static let documentShell = #"""
    <!doctype html>
    <html data-theme="khaki" data-language="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data: file: https: http: markv-image:">
      <style>
        :root { color-scheme:light; --paper:#fdfcf9; --ink:#22231f; --muted:#72736d; --accent:#ba402a; --line:#ebe7de; --inline:#f7f5f0; --table:#faf8f3; --quote:#5d5f58; }
        :root[data-theme="white"] { --paper:#fff; --ink:#222321; --muted:#737570; --line:#e8e8e3; --inline:#f3f3f0; --table:#f7f7f4; --quote:#60625d; }
        * { box-sizing:border-box; }
        html,body { margin:0; min-height:100%; background:var(--paper); }
        body { color:var(--ink); font-family:"New York",Georgia,serif; -webkit-font-smoothing:antialiased; transition:background .18s ease; }
        ::-webkit-scrollbar { width:5px; height:5px; }
        ::-webkit-scrollbar-track { background:transparent; }
        ::-webkit-scrollbar-thumb { background:transparent; border-radius:999px; }
        :hover::-webkit-scrollbar-thumb { background:rgba(114,115,109,.28); }
        ::-webkit-scrollbar-thumb:hover { background:rgba(114,115,109,.48); }
        #editor { max-width:920px; min-height:100vh; margin:0 auto; padding:24px 56px 160px; font-size:var(--editor-font-size,17px); line-height:1.78; caret-color:var(--accent); outline:none; }
        #editor:empty::before { content:"Start writing…"; color:var(--muted); opacity:.45; pointer-events:none; }
        :root[data-language="zh"] #editor:empty::before { content:"开始写作…"; }
        #editor > * { transition:opacity .16s ease; }
        body.focus-mode #editor > * { opacity:.24; }
        body.focus-mode #editor > .active-block { opacity:1; }
        body.pdf-export #editor { min-height:0; padding-bottom:24px; }
        body.pdf-export.focus-mode #editor > * { opacity:1; }
        body.pdf-export #editor:empty::before, body.pdf-export #editor:focus p:empty::after { content:none; }
        ::selection { background:rgba(186,64,42,.16); }
        h1,h2,h3,h4,h5,h6 { color:var(--ink); line-height:1.2; margin:1.7em 0 .55em; letter-spacing:-.022em; }
        h1 { margin-top:0; font-size:2.55em; font-weight:700; padding-bottom:.32em; border-bottom:1px solid var(--line); }
        h2 { font-size:1.72em; } h3 { font-size:1.28em; } h4,h5,h6 { font-size:1em; font-family:"Avenir Next",sans-serif; letter-spacing:.02em; }
        p { margin:0 0 1.18em; }
        a { color:var(--accent); text-decoration-thickness:1px; text-underline-offset:3px; }
        strong { font-weight:700; } del { color:var(--muted); }
        blockquote { margin:1.55em 0; padding:.18em 0 .18em 1.25em; border-left:3px solid var(--accent); color:var(--quote); font-style:italic; }
        blockquote p:last-child { margin-bottom:0; }
        ul,ol { padding-left:1.45em; margin:0 0 1.3em; } li { padding-left:.22em; margin:.25em 0; } li::marker { color:var(--accent); }
        .task-list { list-style:none; padding-left:.2em; } .task-item { padding-left:0; }
        input[type=checkbox] { appearance:none; width:15px; height:15px; margin:0 8px 0 0; border:1.5px solid var(--muted); border-radius:4px; vertical-align:-2px; }
        input[type=checkbox]:checked { border-color:var(--accent); background:var(--accent); box-shadow:inset 0 0 0 3px var(--paper); }
        code { font-family:"SF Mono",ui-monospace,monospace; font-size:.82em; background:var(--inline); padding:.14em .34em; border-radius:4px; }
        pre { overflow:auto; margin:1.6em 0; padding:20px 22px; background:#22231f; color:#eee9dc; border-radius:9px; line-height:1.62; white-space:pre-wrap; box-shadow:0 8px 25px rgba(31,33,31,.08); }
        pre code { padding:0; color:inherit; background:transparent; }
        hr { border:0; border-top:1px solid var(--line); margin:2.5em 0; }
        img { display:block; max-width:100%; height:auto; margin:1.5em auto; border-radius:6px; }
        .table-wrap { overflow:auto; margin:1.55em 0; border:1px solid var(--line); border-radius:8px; }
        table { width:100%; border-collapse:collapse; font-family:"Avenir Next",sans-serif; font-size:.85em; }
        th,td { min-width:90px; padding:9px 12px; text-align:left; border-right:1px solid var(--line); border-bottom:1px solid var(--line); }
        th:last-child,td:last-child { border-right:0; } tbody tr:last-child td { border-bottom:0; }
        th { font-size:.78em; letter-spacing:.05em; text-transform:uppercase; background:var(--table); }
        #editor:focus p:empty::after { content:"Type Markdown naturally…"; color:var(--muted); opacity:.34; }
        :root[data-language="zh"] #editor:focus p:empty::after { content:"自然地输入 Markdown…"; }
        @media print {
          @page { size:A4 portrait; margin:0; }
          * { -webkit-print-color-adjust:exact; print-color-adjust:exact; }
          html,body { min-height:0; }
          #editor { max-width:none; min-height:0; padding:0; font-size:11.5pt; line-height:1.62; }
          #editor:empty::before, #editor:focus p:empty::after { content:none; }
          h1,h2,h3,h4,h5,h6 { break-after:avoid-page; }
          pre,blockquote,.table-wrap,img { break-inside:avoid-page; box-shadow:none; }
        }
        @media(max-width:680px){ #editor{ padding:22px 30px 100px; } h1{font-size:2.1em;} }
      </style>
    </head>
    <body>
      <main id="editor" contenteditable="true" spellcheck="true" role="textbox" aria-multiline="true"></main>
      <script>
        const editor = document.getElementById('editor');
        let applyingNative = false;
        let lastMarkdown = '';
        let inputTimer = null;
        let typewriterMode = false;
        let aiEnabled = false;
        let pendingAISelectionRange = null;
        let pendingAISlashBlock = null;
        const maximumImportedImageBytes = 25 * 1024 * 1024;
        let pendingImageRange = null;

        function markvSetPresentation(theme, focus, typewriter, language, enabledAI, fontSize) {
          document.documentElement.dataset.theme = theme;
          document.documentElement.dataset.language = language || 'en';
          document.documentElement.style.setProperty('--editor-font-size', `${Math.min(30, Math.max(12, Number(fontSize) || 17))}px`);
          document.body.classList.toggle('focus-mode', !!focus);
          typewriterMode = !!typewriter;
          aiEnabled = !!enabledAI;
          updateActiveBlock(false);
        }

        function markvSetContent(html, markdown, theme, focus, typewriter, language, enabledAI, fontSize) {
          applyingNative = true;
          pendingImageRange = null;
          pendingAISelectionRange = null;
          pendingAISlashBlock = null;
          markvSetPresentation(theme, focus, typewriter, language, enabledAI, fontSize);
          editor.innerHTML = html || '<p><br></p>';
          lastMarkdown = markdown;
          decorateDocument();
          applyingNative = false;
        }

        function decorateDocument() {
          editor.querySelectorAll('input[type=checkbox]').forEach(box => box.setAttribute('contenteditable','false'));
          refreshHeadingIDs();
          updateActiveBlock(false);
        }

        function refreshHeadingIDs() {
          const used = {};
          editor.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(heading => {
            let base = slug(heading.textContent);
            let count = used[base] || 0;
            used[base] = count + 1;
            heading.id = count ? `${base}-${count}` : base;
          });
        }

        function slug(text) {
          const value = text.toLowerCase().trim().replace(/[^\p{L}\p{N}]+/gu,'-').replace(/^-+|-+$/g,'');
          return value || 'section';
        }

        function activeTopBlock() {
          const selection = window.getSelection();
          if (!selection || !selection.anchorNode) return null;
          let node = selection.anchorNode.nodeType === Node.ELEMENT_NODE ? selection.anchorNode : selection.anchorNode.parentElement;
          while (node && node.parentElement !== editor) node = node.parentElement;
          return node && node.parentElement === editor ? node : null;
        }

        function updateActiveBlock(scroll) {
          editor.querySelectorAll(':scope > .active-block').forEach(node => node.classList.remove('active-block'));
          const block = activeTopBlock();
          if (!block) return;
          block.classList.add('active-block');
          if ((scroll || typewriterMode) && document.activeElement === editor) {
            block.scrollIntoView({block:'center', behavior:scroll ? 'smooth' : 'auto'});
          }
        }

        function scheduleChange(immediate=false) {
          if (applyingNative) return;
          clearTimeout(inputTimer);
          const send = () => {
            decorateDocument();
            const markdown = toMarkdown();
            lastMarkdown = markdown;
            window.webkit.messageHandlers.editorChanged.postMessage(markdown);
          };
          if (immediate) send(); else inputTimer = setTimeout(send, 140);
        }

        function rememberImageInsertionPoint(range=null) {
          const selection = window.getSelection();
          const source = range || (selection && selection.rangeCount ? selection.getRangeAt(0) : null);
          pendingImageRange = source ? source.cloneRange() : null;
        }

        function caretRangeAtPoint(x, y) {
          if (document.caretRangeFromPoint) return document.caretRangeFromPoint(x, y);
          const position = document.caretPositionFromPoint?.(x, y);
          if (!position) return null;
          const range = document.createRange();
          range.setStart(position.offsetNode, position.offset);
          range.collapse(true);
          return range;
        }

        function transferImageFile(file) {
          if (!file || !String(file.type || '').startsWith('image/')) return false;
          if (file.size > maximumImportedImageBytes) {
            window.webkit.messageHandlers.imageImported.postMessage({error:'tooLarge'});
            return true;
          }
          const reader = new FileReader();
          reader.onload = () => {
            const result = String(reader.result || '');
            const comma = result.indexOf(',');
            if (comma < 0) return;
            window.webkit.messageHandlers.imageImported.postMessage({
              base64: result.slice(comma + 1),
              mimeType: file.type || '',
              name: file.name || ''
            });
          };
          reader.readAsDataURL(file);
          return true;
        }

        function requestSlashAI() {
          if (!aiEnabled) return false;
          const block = activeTopBlock();
          if (!block || !['P','DIV'].includes(block.tagName) || block.textContent !== '/') {
            if (pendingAISlashBlock && pendingAISlashBlock?.textContent !== '/') {
              pendingAISlashBlock = null;
            }
            return false;
          }
          if (pendingAISlashBlock === block) return false;
          pendingAISlashBlock = block;
          window.webkit.messageHandlers.aiEvent.postMessage({type:'slash'});
          return true;
        }

        function captureAISelection() {
          const selection = window.getSelection();
          if (!selection || !selection.rangeCount || selection.isCollapsed) {
            window.webkit.messageHandlers.aiEvent.postMessage({type:'selection', text:''});
            return;
          }
          const range = selection.getRangeAt(0);
          const container = range.commonAncestorContainer.nodeType === Node.ELEMENT_NODE
            ? range.commonAncestorContainer
            : range.commonAncestorContainer.parentElement;
          if (!container || !editor.contains(container)) {
            window.webkit.messageHandlers.aiEvent.postMessage({type:'selection', text:''});
            return;
          }
          pendingAISelectionRange = range.cloneRange();
          window.webkit.messageHandlers.aiEvent.postMessage({
            type:'selection',
            text: selection.toString()
          });
        }

        function restoreAISelection(collapseToEnd=false) {
          if (!pendingAISelectionRange) return false;
          const selection = window.getSelection();
          selection.removeAllRanges();
          const range = pendingAISelectionRange.cloneRange();
          if (collapseToEnd) range.collapse(false);
          selection.addRange(range);
          editor.focus();
          return true;
        }

        editor.addEventListener('paste', event => {
          const item = Array.from(event.clipboardData?.items || []).find(candidate =>
            candidate.kind === 'file' && String(candidate.type || '').startsWith('image/')
          );
          const file = item?.getAsFile();
          if (!file) return;
          event.preventDefault();
          rememberImageInsertionPoint();
          transferImageFile(file);
        });

        editor.addEventListener('dragover', event => {
          const hasImage = Array.from(event.dataTransfer?.items || []).some(item =>
            item.kind === 'file' && String(item.type || '').startsWith('image/')
          );
          if (!hasImage) return;
          event.preventDefault();
          event.dataTransfer.dropEffect = 'copy';
        });

        editor.addEventListener('drop', event => {
          const file = Array.from(event.dataTransfer?.files || []).find(candidate =>
            String(candidate.type || '').startsWith('image/')
          );
          if (!file) return;
          event.preventDefault();
          rememberImageInsertionPoint(caretRangeAtPoint(event.clientX, event.clientY));
          transferImageFile(file);
        });

        editor.addEventListener('input', () => {
          const converted = applyMarkdownShortcut();
          requestSlashAI();
          scheduleChange(converted);
        });
        editor.addEventListener('change', () => scheduleChange(true));
        editor.addEventListener('blur', () => scheduleChange(true));
        editor.addEventListener('beforeinput', event => {
          if (event.inputType !== 'insertParagraph') return;
          if (applyCodeFenceShortcut()) {
            event.preventDefault();
            scheduleChange(true);
          }
        });
        editor.addEventListener('keydown', event => {
          if (event.key === 'Enter' && applyCodeFenceShortcut()) {
            event.preventDefault();
            scheduleChange(true);
          }
        });
        document.addEventListener('selectionchange', () => updateActiveBlock(false));

        function applyMarkdownShortcut() {
          if (applyTaskItemShortcut()) return true;
          const block = activeTopBlock();
          if (!block || !['P','DIV'].includes(block.tagName)) return false;
          const shortcut = globalThis.markvDetectShortcut(block.textContent);
          if (!shortcut || shortcut.type === 'code') return false;
          let html = null;
          let focusSelector = null;
          switch (shortcut.type) {
            case 'heading': html = `<h${shortcut.level}><br></h${shortcut.level}>`; break;
            case 'quote': html = '<blockquote><p><br></p></blockquote>'; focusSelector = 'p'; break;
            case 'unordered': html = '<ul><li><br></li></ul>'; focusSelector = 'li'; break;
            case 'ordered': html = '<ol><li><br></li></ol>'; focusSelector = 'li'; break;
            case 'task':
              html = `<ul class="task-list"><li class="task-item"><input type="checkbox" contenteditable="false" ${shortcut.checked ? 'checked' : ''}> <br></li></ul>`;
              focusSelector = 'li';
              break;
          }
          if (!html) return false;
          replaceBlock(block, html, focusSelector);
          return true;
        }

        function applyTaskItemShortcut() {
          const selection = window.getSelection();
          if (!selection || !selection.anchorNode) return false;
          let node = selection.anchorNode.nodeType === Node.ELEMENT_NODE ? selection.anchorNode : selection.anchorNode.parentElement;
          while (node && node !== editor && node.tagName !== 'LI') node = node.parentElement;
          if (!node || node === editor || node.tagName !== 'LI') return false;
          const task = globalThis.markvDetectTaskItem(node.textContent);
          if (!task) return false;

          const list = node.closest('ul');
          if (!list) return false;
          list.classList.add('task-list');
          node.classList.add('task-item');
          node.innerHTML = `<input type="checkbox" contenteditable="false" ${task.checked ? 'checked' : ''}> \u200B`;
          placeCaretAtEnd(node);
          return true;
        }

        function applyCodeFenceShortcut() {
          const block = activeTopBlock();
          if (!block || !['P','DIV'].includes(block.tagName)) return false;
          const shortcut = globalThis.markvDetectShortcut(block.textContent);
          if (!shortcut || shortcut.type !== 'code') return false;
          replaceBlock(block, `<pre><code class="language-${shortcut.language}"><br></code></pre><p><br></p>`, 'code');
          return true;
        }

        function replaceBlock(block, html, focusSelector) {
          const template = document.createElement('template');
          template.innerHTML = html;
          const nodes = Array.from(template.content.childNodes);
          block.replaceWith(template.content);
          const targetRoot = nodes[0];
          const target = focusSelector ? targetRoot.querySelector(focusSelector) : targetRoot;
          placeCaretAtEnd(target);
        }

        function placeCaretAtEnd(element) {
          if (!element) return;
          const range = document.createRange();
          range.selectNodeContents(element);
          range.collapse(false);
          const selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
          editor.focus();
        }

        function markvText(english, chinese) {
          return document.documentElement.dataset.language === 'zh' ? chinese : english;
        }

        function normalizedMarkdownImageSource(value) {
          return String(value || '')
            .replace(/&(?:#x20|#32);/gi, ' ')
            .replace(/ /g, '%20');
        }

        function insertImageSource(value) {
          const source = normalizedMarkdownImageSource(value);
          if (!source) return;
          const image = document.createElement('img');
          const isRelative = !/^[a-z][a-z0-9+.-]*:/i.test(source) && !source.startsWith('/');
          if (isRelative) {
            image.src = `markv-image:///${source.replace(/^\/+/, '')}`;
            image.setAttribute('data-markv-src', source);
          } else {
            image.src = source;
          }
          document.execCommand('insertHTML', false, image.outerHTML);
        }

        window.markvCommand = function(command, value) {
          if (command === 'jump') {
            document.getElementById(value)?.scrollIntoView({behavior:'smooth',block:'start'});
            return;
          }
          if (command === 'captureAISelection') {
            captureAISelection();
            return;
          }
          if (command === 'clearAIContext') {
            pendingAISelectionRange = null;
            pendingAISlashBlock = null;
            return;
          }
          if (command === 'replaceAISelection') {
            if (restoreAISelection(false)) {
              document.execCommand('insertText', false, value);
              pendingAISelectionRange = null;
              scheduleChange(true);
            }
            return;
          }
          if (command === 'insertAfterAISelection') {
            if (pendingAISelectionRange) {
              let node = pendingAISelectionRange.endContainer.nodeType === Node.ELEMENT_NODE
                ? pendingAISelectionRange.endContainer
                : pendingAISelectionRange.endContainer.parentElement;
              while (node && node.parentElement !== editor) node = node.parentElement;
              const paragraph = document.createElement('p');
              paragraph.textContent = value;
              if (node && node.parentElement === editor) {
                node.insertAdjacentElement('afterend', paragraph);
              } else {
                editor.appendChild(paragraph);
              }
              placeCaretAtEnd(paragraph);
              pendingAISelectionRange = null;
              scheduleChange(true);
            }
            return;
          }
          if (command === 'replaceAISlashHTML') {
            if (pendingAISlashBlock && pendingAISlashBlock.isConnected) {
              const template = document.createElement('template');
              template.innerHTML = value;
              const nodes = Array.from(template.content.childNodes);
              pendingAISlashBlock.replaceWith(template.content);
              pendingAISlashBlock = null;
              const target = nodes.reverse().find(node => node.nodeType === Node.ELEMENT_NODE);
              if (target) placeCaretAtEnd(target);
              scheduleChange(true);
            }
            return;
          }
          editor.focus();
          if (command === 'insertImage' && pendingImageRange) {
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(pendingImageRange);
            pendingImageRange = null;
          }
          switch (command) {
            case 'focus': break;
            case 'block': document.execCommand('formatBlock', false, value); break;
            case 'bold': document.execCommand('bold'); break;
            case 'italic': document.execCommand('italic'); break;
            case 'strike': document.execCommand('strikeThrough'); break;
            case 'unorderedList': document.execCommand('insertUnorderedList'); break;
            case 'orderedList': document.execCommand('insertOrderedList'); break;
            case 'horizontalRule': document.execCommand('insertHorizontalRule'); break;
            case 'inlineCode': wrapSelection('code'); break;
            case 'taskList': document.execCommand('insertHTML',false,`<ul class="task-list"><li class="task-item"><input type="checkbox" contenteditable="false"> ${markvText('Task','任务')}</li></ul><p><br></p>`); break;
            case 'table': {
              const column = markvText('Column','列');
              const value = markvText('Value','内容');
              document.execCommand('insertHTML',false,`<div class="table-wrap"><table><thead><tr><th>${column} 1</th><th>${column} 2</th><th>${column} 3</th></tr></thead><tbody><tr><td>${value}</td><td>${value}</td><td>${value}</td></tr><tr><td>${value}</td><td>${value}</td><td>${value}</td></tr></tbody></table></div><p><br></p>`);
              break;
            }
            case 'link': {
              const url = window.prompt(markvText('Insert link','插入链接'), 'https://');
              if (url) document.execCommand('createLink',false,url);
              break;
            }
            case 'image': {
              const url = window.prompt(markvText('Insert image URL or relative path','插入图片网址或相对路径'), 'images/example.png');
              if (url) insertImageSource(url);
              break;
            }
            case 'insertImage': insertImageSource(value); break;
          }
          scheduleChange(true);
        };

        function wrapSelection(tagName) {
          const selection = window.getSelection();
          if (!selection || !selection.rangeCount || selection.isCollapsed) return;
          const range = selection.getRangeAt(0);
          const wrapper = document.createElement(tagName);
          try { range.surroundContents(wrapper); selection.removeAllRanges(); selection.selectAllChildren(wrapper); }
          catch (_) { document.execCommand('insertHTML',false,`<${tagName}>${selection.toString()}</${tagName}>`); }
        }

        function inline(node) {
          if (!node) return '';
          if (node.nodeType === Node.TEXT_NODE) return node.nodeValue.replace(/\u200B/g,'');
          if (node.nodeType !== Node.ELEMENT_NODE) return '';
          const tag = node.tagName.toLowerCase();
          const content = Array.from(node.childNodes).map(inline).join('');
          switch (tag) {
            case 'strong': case 'b': return `**${content}**`;
            case 'em': case 'i': return `*${content}*`;
            case 's': case 'del': case 'strike': return `~~${content}~~`;
            case 'code': return node.parentElement?.tagName.toLowerCase() === 'pre' ? content : `\`${content}\``;
            case 'a': return `[${content}](${node.getAttribute('href') || ''})`;
            case 'img': {
              const source = node.getAttribute('data-markv-src') || node.getAttribute('src') || '';
              return `![${node.getAttribute('alt') || ''}](${normalizedMarkdownImageSource(source)})`;
            }
            case 'br': return '\n';
            case 'input': return node.type === 'checkbox' ? (node.checked ? '[x] ' : '[ ] ') : '';
            default: return content;
          }
        }

        function block(node, depth=0) {
          if (!node) return '';
          if (node.nodeType === Node.TEXT_NODE) return node.nodeValue.trim() ? `${node.nodeValue}\n\n` : '';
          if (node.nodeType !== Node.ELEMENT_NODE) return '';
          const tag = node.tagName.toLowerCase();
          if (/^h[1-6]$/.test(tag)) return `${'#'.repeat(Number(tag[1]))} ${inline(node).trim()}\n\n`;
          if (tag === 'p') return `${inline(node).replace(/\n+$/,'').trimEnd()}\n\n`;
          if (tag === 'div' && node.classList.contains('table-wrap')) return block(node.querySelector('table'), depth);
          if (tag === 'div') return `${inline(node).trimEnd()}\n\n`;
          if (tag === 'blockquote') {
            const content = Array.from(node.childNodes).map(child => block(child,depth+1)).join('').trimEnd();
            return content.split('\n').map(line => `> ${line}`).join('\n') + '\n\n';
          }
          if (tag === 'ul' || tag === 'ol') {
            const ordered = tag === 'ol';
            return Array.from(node.children).filter(child => child.tagName.toLowerCase() === 'li').map((li,index) => {
              const direct = Array.from(li.childNodes).filter(child => !(child.nodeType === Node.ELEMENT_NODE && ['ul','ol'].includes(child.tagName.toLowerCase()))).map(inline).join('').trim();
              const prefix = ordered ? `${index+1}. ` : '- ';
              const nested = Array.from(li.children).filter(child => ['ul','ol'].includes(child.tagName.toLowerCase())).map(child => block(child,depth+1).trimEnd().split('\n').map(line => `  ${line}`).join('\n')).join('\n');
              return prefix + direct + (nested ? `\n${nested}` : '');
            }).join('\n') + '\n\n';
          }
          if (tag === 'pre') {
            const code = node.querySelector('code');
            const language = (code?.className || '').replace(/^language-/,'');
            return `\`\`\`${language}\n${(code || node).textContent.replace(/\n$/,'')}\n\`\`\`\n\n`;
          }
          if (tag === 'hr') return '---\n\n';
          if (tag === 'table') return tableMarkdown(node);
          if (tag === 'br') return '\n';
          return `${inline(node).trimEnd()}\n\n`;
        }

        function tableMarkdown(table) {
          const rows = Array.from(table.querySelectorAll('tr')).map(row => Array.from(row.children).map(cell => inline(cell).trim().replace(/\|/g,'\\|')));
          if (!rows.length) return '';
          const width = Math.max(...rows.map(row => row.length));
          const normalized = rows.map(row => Array.from({length:width},(_,i) => row[i] || ''));
          const lines = [`| ${normalized[0].join(' | ')} |`, `| ${Array(width).fill('---').join(' | ')} |`];
          normalized.slice(1).forEach(row => lines.push(`| ${row.join(' | ')} |`));
          return lines.join('\n') + '\n\n';
        }

        function toMarkdown() {
          return Array.from(editor.childNodes).map(node => block(node)).join('').replace(/\n{3,}/g,'\n\n').trimEnd() + '\n';
        }

        window.markvSetContent = markvSetContent;
        window.markvSetPresentation = markvSetPresentation;
      </script>
    </body>
    </html>
    """#
}
