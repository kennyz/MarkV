import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct MarkdownFile: Identifiable, Hashable {
    let url: URL
    let modifiedAt: Date?
    let byteCount: Int?
    let indexedText: String
    let preview: String

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var displayName: String { url.deletingPathExtension().lastPathComponent }

    init(url: URL, modifiedAt: Date?, byteCount: Int?, indexedText: String) {
        self.url = url
        self.modifiedAt = modifiedAt
        self.byteCount = byteCount
        self.indexedText = indexedText
        self.preview = Self.previewText(from: indexedText)
    }

    func matches(_ query: String) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).foldedForSearch }
        guard !terms.isEmpty else { return true }

        let searchable = "\(displayName)\n\(indexedText)".foldedForSearch
        return terms.allSatisfy(searchable.contains)
    }

    static func previewText(from markdown: String, limit: Int = 110) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var fragments: [String] = []
        var headingFallback = ""
        var insideFence = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                insideFence.toggle()
                continue
            }
            guard !insideFence, !line.isEmpty else { continue }

            let isHeading = line.range(
                of: #"^#{1,6}\s+"#,
                options: .regularExpression
            ) != nil
            let cleaned = cleanMarkdownLine(line)
            guard !cleaned.isEmpty else { continue }

            if isHeading {
                if headingFallback.isEmpty { headingFallback = cleaned }
                continue
            }

            fragments.append(cleaned)
            if fragments.joined(separator: " ").count >= limit || fragments.count == 2 {
                break
            }
        }

        let value = (fragments.isEmpty ? headingFallback : fragments.joined(separator: " "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > limit else { return value }
        return String(value.prefix(max(1, limit - 1))).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func cleanMarkdownLine(_ line: String) -> String {
        line
            .replacingOccurrences(
                of: #"^\s*(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX]\]\s*)?|\d+[.)]\s+)"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"!\[([^\]]*)\]\([^)]*\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]*\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[*_~`]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var foldedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum AppearanceTheme: String, CaseIterable, Identifiable {
    case khaki
    case white

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .khaki: "Khaki"
        case .white: "White"
        }
    }

    var detail: String {
        switch self {
        case .khaki: "Warm paper"
        case .white: "Clean neutral"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private enum Keys {
        static let recentFiles = "markv.recentFiles"
        static let lastFolder = "markv.lastFolder"
        static let appearanceTheme = "markv.appearanceTheme"
        static let focusMode = "markv.focusMode"
        static let typewriterMode = "markv.typewriterMode"
        static let appLanguage = "markv.appLanguage"
    }

    @Published private(set) var currentFolder: URL?
    @Published private(set) var files: [MarkdownFile] = []
    @Published private(set) var recentFiles: [URL] = []
    @Published private(set) var currentFile: URL?
    @Published private(set) var documentText = ""
    @Published private(set) var isDirty = false
    @Published var errorMessage: String?
    @Published var appearanceTheme: AppearanceTheme {
        didSet { defaults.set(appearanceTheme.rawValue, forKey: Keys.appearanceTheme) }
    }
    @Published var focusMode: Bool {
        didSet { defaults.set(focusMode, forKey: Keys.focusMode) }
    }
    @Published var typewriterMode: Bool {
        didSet { defaults.set(typewriterMode, forKey: Keys.typewriterMode) }
    }
    @Published var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }
    @Published var editorCommand: EditorCommand?

    private let defaults: UserDefaults
    private var previewCache: [String: String] = [:]

    init(defaults: UserDefaults = .standard, restoreLastFolder: Bool = true) {
        self.defaults = defaults
        self.appearanceTheme = AppearanceTheme(
            rawValue: defaults.string(forKey: Keys.appearanceTheme) ?? ""
        ) ?? .khaki
        self.focusMode = defaults.bool(forKey: Keys.focusMode)
        self.typewriterMode = defaults.bool(forKey: Keys.typewriterMode)
        self.appLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Keys.appLanguage) ?? ""
        ) ?? .english

        let stored = defaults.stringArray(forKey: Keys.recentFiles) ?? []
        self.recentFiles = Self.normalizedRecents(
            stored.map { URL(fileURLWithPath: $0) }
        ).filter { FileManager.default.fileExists(atPath: $0.path) }
        self.previewCache = Dictionary(uniqueKeysWithValues: recentFiles.map { url in
            (url.standardizedFileURL.path, Self.readPreview(at: url))
        })

        if restoreLastFolder,
           let path = defaults.string(forKey: Keys.lastFolder) {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            if Self.isDirectory(folder) {
                currentFolder = folder
                refreshFiles()
            }
        }
    }

    nonisolated static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased())
    }

    nonisolated static func normalizedRecents(_ urls: [URL], limit: Int = 12) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for url in urls {
            let canonical = url.standardizedFileURL
            guard seen.insert(canonical.path).inserted else { continue }
            result.append(canonical)
            if result.count == limit { break }
        }
        return result
    }

    func text(_ english: String) -> String {
        appLanguage.text(english)
    }

    func localizedFormat(_ english: String, _ arguments: CVarArg...) -> String {
        String(format: appLanguage.text(english), arguments: arguments)
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func chooseDirectory() {
        guard confirmDocumentTransition() else { return }

        let panel = NSOpenPanel()
        panel.title = text("Choose a Markdown folder")
        panel.prompt = text("Open Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentFolder

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        openDirectory(folder)
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = text("Open a Markdown file")
        panel.prompt = text("Open")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentFolder
        panel.allowedContentTypes = ["md", "markdown", "mdown", "mkd"].compactMap {
            UTType(filenameExtension: $0)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openRecent(url)
    }

    func openDirectory(_ folder: URL) {
        guard Self.isDirectory(folder) else {
            errorMessage = text("That folder is no longer available.")
            return
        }

        currentFolder = folder.standardizedFileURL
        currentFile = nil
        documentText = ""
        isDirty = false
        defaults.set(currentFolder?.path, forKey: Keys.lastFolder)
        refreshFiles()
    }

    func refreshFiles() {
        guard let folder = currentFolder else {
            files = []
            return
        }

        do {
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )

            files = urls.compactMap { url in
                guard Self.isMarkdownFile(url) else { return nil }
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile != false else { return nil }
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                let file = MarkdownFile(
                    url: url,
                    modifiedAt: values?.contentModificationDate,
                    byteCount: values?.fileSize,
                    indexedText: text
                )
                previewCache[url.standardizedFileURL.path] = file.preview
                return file
            }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            files = []
            errorMessage = localizedFormat("Markv could not read this folder: %@", error.localizedDescription)
        }
    }

    func openFile(_ url: URL) {
        guard url != currentFile else { return }
        guard confirmDocumentTransition() else { return }
        loadFile(url)
    }

    func files(matching query: String) -> [MarkdownFile] {
        files.filter { $0.matches(query) }
    }

    func preview(for url: URL) -> String {
        previewCache[url.standardizedFileURL.path] ?? ""
    }

    @discardableResult
    func renameCurrentFile(to requestedName: String) -> Bool {
        guard let source = currentFile else { return false }

        let originalExtension = source.pathExtension
        var baseName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedExtension = ".\(originalExtension)"
        if baseName.lowercased().hasSuffix(typedExtension.lowercased()) {
            baseName.removeLast(typedExtension.count)
            baseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let containsControlCharacter = baseName.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
        guard !baseName.isEmpty,
              baseName != ".",
              baseName != "..",
              !baseName.contains("/"),
              !baseName.contains(":"),
              !containsControlCharacter else {
            errorMessage = text("Enter a valid file name without path separators.")
            return false
        }

        let parent = source.deletingLastPathComponent()
        let destination = parent
            .appendingPathComponent(baseName)
            .appendingPathExtension(originalExtension)
            .standardizedFileURL
        let sourceURL = source.standardizedFileURL
        guard destination != sourceURL else { return true }

        let isCaseOnlyRename = destination.path.caseInsensitiveCompare(sourceURL.path) == .orderedSame
        if FileManager.default.fileExists(atPath: destination.path), !isCaseOnlyRename {
            errorMessage = localizedFormat("A file named %@ already exists.", destination.lastPathComponent)
            return false
        }

        do {
            if isCaseOnlyRename {
                let temporary = parent.appendingPathComponent(".markv-rename-\(UUID().uuidString)")
                try FileManager.default.moveItem(at: sourceURL, to: temporary)
                do {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                } catch {
                    try? FileManager.default.moveItem(at: temporary, to: sourceURL)
                    throw error
                }
            } else {
                try FileManager.default.moveItem(at: sourceURL, to: destination)
            }

            currentFile = destination
            recentFiles = recentFiles.map {
                $0.standardizedFileURL == sourceURL ? destination : $0
            }
            recentFiles = Self.normalizedRecents(recentFiles)
            persistRecents()

            if let preview = previewCache.removeValue(forKey: sourceURL.path) {
                previewCache[destination.path] = preview
            }
            refreshFiles()
            return true
        } catch {
            errorMessage = localizedFormat("Markv could not rename the file: %@", error.localizedDescription)
            return false
        }
    }

    func openRecent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            removeRecent(url)
            errorMessage = text("That recent file is no longer available.")
            return
        }
        guard confirmDocumentTransition() else { return }

        let parent = url.deletingLastPathComponent()
        if parent.standardizedFileURL != currentFolder?.standardizedFileURL {
            currentFolder = parent
            defaults.set(parent.path, forKey: Keys.lastFolder)
            refreshFiles()
        }
        loadFile(url)
    }

    @discardableResult
    func openExternalFiles(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: { candidate in
            Self.isMarkdownFile(candidate)
                && FileManager.default.fileExists(atPath: candidate.path)
                && !Self.isDirectory(candidate)
        }) else {
            errorMessage = text("Drop a Markdown file (.md, .markdown, .mdown, or .mkd) to open it.")
            return false
        }

        openRecent(url)
        return true
    }

    func updateDocument(_ newValue: String) {
        documentText = newValue
        isDirty = currentFile != nil
    }

    func performEditorAction(_ action: EditorAction) {
        editorCommand = EditorCommand(action: action)
    }

    func choosePDFExportDestination() {
        guard let currentFile else { return }

        let panel = NSSavePanel()
        panel.title = text("Export as PDF")
        panel.prompt = text("Export")
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.directoryURL = currentFile.deletingLastPathComponent()
        panel.nameFieldStringValue = currentFile
            .deletingPathExtension()
            .appendingPathExtension("pdf")
            .lastPathComponent

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportPDF(to: url)
    }

    func exportPDF(to url: URL) {
        guard currentFile != nil else { return }
        let destination = url.pathExtension.lowercased() == "pdf"
            ? url
            : url.appendingPathExtension("pdf")
        performEditorAction(.exportPDF(destination))
    }

    func handlePDFExportResult(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            errorMessage = localizedFormat(
                "Markv could not export the PDF: %@",
                text(error.localizedDescription)
            )
        }
    }

    var outline: [DocumentOutlineItem] {
        DocumentIntelligence.outline(from: documentText)
    }

    var statistics: DocumentStatistics {
        DocumentIntelligence.statistics(for: documentText)
    }

    func createFromStarterTemplate() {
        guard confirmDocumentTransition() else { return }

        let panel = NSSavePanel()
        panel.title = text("New from Markdown Starter")
        panel.prompt = text("Create")
        panel.nameFieldStringValue = MarkdownTemplate.starter.suggestedFilename
        panel.directoryURL = currentFolder
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension.isEmpty {
            url.appendPathExtension("md")
        }
        guard Self.isMarkdownFile(url) else {
            errorMessage = text("The template must be saved as a Markdown file.")
            return
        }

        do {
            try MarkdownTemplate.starter.content.write(to: url, atomically: true, encoding: .utf8)
            let parent = url.deletingLastPathComponent()
            currentFolder = parent
            defaults.set(parent.path, forKey: Keys.lastFolder)
            refreshFiles()
            loadFile(url)
        } catch {
            errorMessage = localizedFormat("Markv could not create the template: %@", error.localizedDescription)
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let file = currentFile else { return false }
        do {
            try documentText.write(to: file, atomically: true, encoding: .utf8)
            isDirty = false
            refreshFiles()
            return true
        } catch {
            errorMessage = localizedFormat("Markv could not save %@: %@", file.lastPathComponent, error.localizedDescription)
            return false
        }
    }

    func revealCurrentFile() {
        guard let currentFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([currentFile])
    }

    func removeRecent(_ url: URL) {
        recentFiles.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        persistRecents()
    }

    var currentFileMetadata: String {
        guard let currentFile,
              let attributes = try? FileManager.default.attributesOfItem(atPath: currentFile.path),
              let size = attributes[.size] as? NSNumber else { return "" }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private func loadFile(_ url: URL) {
        guard Self.isMarkdownFile(url) else {
            errorMessage = text("Markv can open Markdown files only.")
            return
        }

        do {
            documentText = try String(contentsOf: url, encoding: .utf8)
            currentFile = url.standardizedFileURL
            isDirty = false
            addRecent(url)
        } catch {
            errorMessage = localizedFormat("Markv could not open %@: %@", url.lastPathComponent, error.localizedDescription)
        }
    }

    private func addRecent(_ url: URL) {
        recentFiles = Self.normalizedRecents([url] + recentFiles)
        previewCache[url.standardizedFileURL.path] = Self.readPreview(at: url)
        persistRecents()
    }

    nonisolated private static func readPreview(at url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return MarkdownFile.previewText(from: text)
    }

    private func persistRecents() {
        defaults.set(recentFiles.map(\.path), forKey: Keys.recentFiles)
    }

    private func confirmDocumentTransition() -> Bool {
        guard isDirty, let currentFile else { return true }

        let alert = NSAlert()
        alert.messageText = localizedFormat("Save changes to %@?", currentFile.lastPathComponent)
        alert.informativeText = text("Your edits will be lost if you don't save them.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: text("Save"))
        alert.addButton(withTitle: text("Cancel"))
        alert.addButton(withTitle: text("Don't Save"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return save()
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }
}
