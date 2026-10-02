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
        static let editorFontSize = "markv.editorFontSize"
        static let sidebarFontSize = "markv.sidebarFontSize"
        static let focusMode = "markv.focusMode"
        static let typewriterMode = "markv.typewriterMode"
        static let appLanguage = "markv.appLanguage"
        static let aiEnabled = "markv.aiEnabled"
        static let aiBaseURL = "markv.aiBaseURL"
        static let aiModel = "markv.aiModel"
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
    static let defaultEditorFontSize = 17.0
    static let defaultSidebarFontSize = 14.0
    static let editorFontSizeRange = 12.0...30.0
    static let sidebarFontSizeRange = 11.0...20.0

    @Published private(set) var editorFontSize: Double {
        didSet { defaults.set(editorFontSize, forKey: Keys.editorFontSize) }
    }
    @Published private(set) var sidebarFontSize: Double {
        didSet { defaults.set(sidebarFontSize, forKey: Keys.sidebarFontSize) }
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
    @Published var aiEnabled: Bool {
        didSet {
            guard AppDistribution.supportsAI else {
                if aiEnabled { aiEnabled = false }
                return
            }
            defaults.set(aiEnabled, forKey: Keys.aiEnabled)
            if !aiEnabled { cancelAIInteraction() }
        }
    }
    @Published var aiBaseURL: String {
        didSet { defaults.set(aiBaseURL, forKey: Keys.aiBaseURL) }
    }
    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Keys.aiModel) }
    }
    @Published var aiAPIKey: String {
        didSet {
            guard AppDistribution.supportsAI else { return }
            do {
                try aiKeyStore.saveAPIKey(aiAPIKey)
            } catch {
                errorMessage = localizedFormat("Markv could not save the API key: %@", error.localizedDescription)
            }
        }
    }
    @Published var aiInstruction = ""
    @Published var aiPromptContext: AIPromptContext?
    @Published private(set) var aiRevision: AIRevision?
    @Published private(set) var aiIsWorking = false
    @Published private(set) var updateStatus: UpdateStatus = .idle
    @Published private(set) var isDefaultMarkdownApplication = false
    @Published private(set) var isChangingMarkdownAssociation = false
    @Published var editorCommand: EditorCommand?

    private let defaults: UserDefaults
    private let aiKeyStore: any AIAPIKeyStoring
    private let aiService: any AICompleting
    private let updateService: any UpdateChecking
    private let markdownFileAssociation: any MarkdownFileAssociationManaging
    let appVersion: String
    private var previewCache: [String: String] = [:]
    private var pendingAIEditAction: AIEditAction?
    private var lastAIRequest: AIRequestContext?
    private var aiTask: Task<Void, Never>?
    private var didRequestAutomaticUpdateCheck = false

    init(
        defaults: UserDefaults = .standard,
        restoreLastFolder: Bool = true,
        aiKeyStore: any AIAPIKeyStoring = AIKeychainStore(),
        aiService: any AICompleting = AIService(),
        updateService: any UpdateChecking = GitHubUpdateService(),
        markdownFileAssociation: any MarkdownFileAssociationManaging = MarkdownFileAssociationManager(),
        appVersion: String = AppVersion.current()
    ) {
        self.defaults = defaults
        self.aiKeyStore = aiKeyStore
        self.aiService = aiService
        self.updateService = updateService
        self.markdownFileAssociation = markdownFileAssociation
        self.appVersion = appVersion
        self.appearanceTheme = AppearanceTheme(
            rawValue: defaults.string(forKey: Keys.appearanceTheme) ?? ""
        ) ?? .khaki
        self.editorFontSize = Self.clampedFontSize(
            (defaults.object(forKey: Keys.editorFontSize) as? Double) ?? Self.defaultEditorFontSize,
            range: Self.editorFontSizeRange,
            fallback: Self.defaultEditorFontSize
        )
        self.sidebarFontSize = Self.clampedFontSize(
            (defaults.object(forKey: Keys.sidebarFontSize) as? Double) ?? Self.defaultSidebarFontSize,
            range: Self.sidebarFontSizeRange,
            fallback: Self.defaultSidebarFontSize
        )
        self.focusMode = defaults.bool(forKey: Keys.focusMode)
        self.typewriterMode = defaults.bool(forKey: Keys.typewriterMode)
        self.appLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Keys.appLanguage) ?? ""
        ) ?? .english
        self.aiEnabled = AppDistribution.supportsAI && defaults.bool(forKey: Keys.aiEnabled)
        self.aiBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? "https://api.openai.com/v1"
        self.aiModel = defaults.string(forKey: Keys.aiModel) ?? ""
        self.aiAPIKey = AppDistribution.supportsAI ? ((try? aiKeyStore.loadAPIKey()) ?? "") : ""

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

    private static func clampedFontSize(_ size: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard size.isFinite else { return fallback }
        return min(max(size.rounded(), range.lowerBound), range.upperBound)
    }

    func setEditorFontSize(_ size: Double) {
        editorFontSize = Self.clampedFontSize(size, range: Self.editorFontSizeRange, fallback: Self.defaultEditorFontSize)
    }

    func setSidebarFontSize(_ size: Double) {
        sidebarFontSize = Self.clampedFontSize(size, range: Self.sidebarFontSizeRange, fallback: Self.defaultSidebarFontSize)
    }

    func increaseFontSize() { setEditorFontSize(editorFontSize + 1) }
    func decreaseFontSize() { setEditorFontSize(editorFontSize - 1) }
    func resetEditorFontSize() { setEditorFontSize(Self.defaultEditorFontSize) }

    func resetFontSizes() {
        resetEditorFontSize()
        setSidebarFontSize(Self.defaultSidebarFontSize)
    }

    nonisolated static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased())
    }

    nonisolated static func isImageFile(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: fileExtension), type.conforms(to: .image) {
            return true
        }
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg"]
            .contains(fileExtension)
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

    func checkForUpdatesAutomatically() async {
        guard AppDistribution.supportsGitHubUpdates else { return }
        guard !didRequestAutomaticUpdateCheck else { return }
        didRequestAutomaticUpdateCheck = true
        await checkForUpdates()
    }

    func refreshMarkdownFileAssociation() {
        isDefaultMarkdownApplication = markdownFileAssociation.isDefaultApplication()
    }

    func setAsDefaultMarkdownApplication() async {
        guard !isChangingMarkdownAssociation else { return }
        isChangingMarkdownAssociation = true
        defer { isChangingMarkdownAssociation = false }

        do {
            try await markdownFileAssociation.setAsDefaultApplication()
            refreshMarkdownFileAssociation()
            if !isDefaultMarkdownApplication {
                errorMessage = text("macOS did not change the Markdown default application.")
            }
        } catch {
            errorMessage = localizedFormat(
                "Markv could not change the Markdown file association: %@",
                error.localizedDescription
            )
            refreshMarkdownFileAssociation()
        }
    }

    func checkForUpdates() async {
        guard AppDistribution.supportsGitHubUpdates else { return }
        guard updateStatus != .checking else { return }
        updateStatus = .checking
        do {
            let release = try await updateService.latestRelease()
            guard let current = SemanticVersion(appVersion),
                  let latest = SemanticVersion(release.version) else {
                updateStatus = .failed
                return
            }
            updateStatus = latest > current ? .available(release) : .upToDate
        } catch {
            updateStatus = .failed
        }
    }

    func openAvailableUpdate() {
        guard AppDistribution.supportsGitHubUpdates else { return }
        guard case .available(let release) = updateStatus else { return }
        NSWorkspace.shared.open(release.pageURL)
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

    @discardableResult
    nonisolated static func clipboardPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    func copyFilePath(_ url: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        return pasteboard.setString(Self.clipboardPath(for: url), forType: .string)
    }

    func confirmMoveFileToTrash(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = localizedFormat("Move %@ to Trash?", url.lastPathComponent)
        alert.informativeText = text("This file will be moved to the Trash.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: text("Move to Trash"))
        alert.addButton(withTitle: text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        moveFileToTrash(url)
    }

    @discardableResult
    func moveFileToTrash(
        _ url: URL,
        operation: ((URL) throws -> Void)? = nil
    ) -> Bool {
        let target = url.standardizedFileURL
        do {
            if let operation {
                try operation(target)
            } else {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: target, resultingItemURL: &trashedURL)
            }

            if currentFile?.standardizedFileURL == target {
                currentFile = nil
                documentText = ""
                isDirty = false
            }
            removeRecent(target)
            previewCache.removeValue(forKey: target.path)
            refreshFiles()
            return true
        } catch {
            errorMessage = localizedFormat(
                "Markv could not move the file to Trash: %@",
                error.localizedDescription
            )
            return false
        }
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

    @discardableResult
    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        if let image = urls.first(where: Self.isImageFile) {
            return importImageFile(image)
        }
        return openExternalFiles(urls)
    }

    func updateDocument(_ newValue: String) {
        documentText = newValue
        isDirty = currentFile != nil
    }

    func performEditorAction(_ action: EditorAction) {
        editorCommand = EditorCommand(action: action)
    }

    var aiConfiguration: AIConfiguration {
        AIConfiguration(baseURL: aiBaseURL, model: aiModel, apiKey: aiAPIKey)
    }

    func beginAISelectionEdit(_ action: AIEditAction) {
        guard AppDistribution.supportsAI else { return }
        guard aiEnabled else {
            errorMessage = text("Enable AI in Settings first.")
            return
        }
        do {
            _ = try aiConfiguration.endpointURL()
        } catch {
            errorMessage = text(error.localizedDescription)
            return
        }
        pendingAIEditAction = action
        performEditorAction(.captureAISelection)
    }

    func handleAIEditorEvent(_ event: EditorAIEvent) {
        guard AppDistribution.supportsAI && aiEnabled else { return }
        switch event {
        case .slash:
            do {
                _ = try aiConfiguration.endpointURL()
            } catch {
                errorMessage = text(error.localizedDescription)
                performEditorAction(.clearAIContext)
                return
            }
            aiInstruction = ""
            aiPromptContext = .insertion
            aiRevision = nil
        case .selection(let value):
            let original = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else {
                pendingAIEditAction = nil
                errorMessage = text("Select text before using AI editing.")
                performEditorAction(.clearAIContext)
                return
            }
            guard original.count <= 100_000 else {
                pendingAIEditAction = nil
                errorMessage = text("The selected text is too long for AI editing.")
                performEditorAction(.clearAIContext)
                return
            }
            let action = pendingAIEditAction ?? .custom
            pendingAIEditAction = nil
            if action == .custom {
                aiInstruction = ""
                aiPromptContext = .selection(original: original)
            } else {
                startAIRequest(.selection(original: original, instruction: action.instruction))
            }
        }
    }

    func submitAIPrompt() {
        guard let context = aiPromptContext else { return }
        let instruction = aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            errorMessage = text("Enter an instruction for AI.")
            return
        }
        guard instruction.count <= 10_000 else {
            errorMessage = text("The AI instruction is too long.")
            return
        }
        aiPromptContext = nil
        aiInstruction = ""
        switch context {
        case .selection(let original):
            startAIRequest(.selection(original: original, instruction: instruction))
        case .insertion:
            startAIRequest(.insertion(instruction: instruction))
        }
    }

    func cancelAIPrompt() {
        aiPromptContext = nil
        aiInstruction = ""
        performEditorAction(.clearAIContext)
    }

    func cancelAIInteraction() {
        aiTask?.cancel()
        aiTask = nil
        aiIsWorking = false
        aiPromptContext = nil
        aiRevision = nil
        aiInstruction = ""
        pendingAIEditAction = nil
        performEditorAction(.clearAIContext)
    }

    func retryAIRevision() {
        guard let lastAIRequest else { return }
        startAIRequest(lastAIRequest)
    }

    func discardAIRevision() {
        aiRevision = nil
        performEditorAction(.clearAIContext)
    }

    func acceptAIRevision(replaceSelection: Bool = true) {
        guard let revision = aiRevision else { return }
        aiRevision = nil
        switch revision.mode {
        case .selection:
            performEditorAction(
                replaceSelection
                    ? .replaceAISelection(revision.revised)
                    : .insertAfterAISelection(revision.revised)
            )
        case .insertion:
            let markdown = AIRequestFactory.normalizedMarkdown(revision.revised)
            let html = MarkdownRenderer.render(markdown, localImageBaseURL: currentFile?.deletingLastPathComponent())
            performEditorAction(.replaceAISlashHTML(html))
        }
    }

    private func startAIRequest(_ context: AIRequestContext) {
        guard AppDistribution.supportsAI && aiEnabled else { return }
        let configuration = aiConfiguration
        do {
            _ = try configuration.endpointURL()
        } catch {
            errorMessage = text(error.localizedDescription)
            return
        }

        aiTask?.cancel()
        aiIsWorking = true
        aiRevision = nil
        lastAIRequest = context
        let messages = AIRequestFactory.messages(for: context)
        let service = aiService
        aiTask = Task { [weak self] in
            do {
                let result = try await service.complete(
                    configuration: configuration,
                    messages: messages
                )
                guard !Task.isCancelled, let self else { return }
                self.aiIsWorking = false
                self.aiTask = nil
                switch context {
                case .selection(let original, _):
                    self.aiRevision = AIRevision(
                        mode: .selection,
                        original: original,
                        revised: result.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                case .insertion:
                    self.aiRevision = AIRevision(
                        mode: .insertion,
                        original: "",
                        revised: AIRequestFactory.normalizedMarkdown(result)
                    )
                }
            } catch is CancellationError {
                guard let self else { return }
                self.aiIsWorking = false
                self.aiTask = nil
            } catch {
                guard let self else { return }
                self.aiIsWorking = false
                self.aiTask = nil
                let description = self.redactedAIErrorDescription(error)
                self.errorMessage = self.localizedFormat(
                    "AI request failed: %@",
                    self.text(description)
                )
            }
        }
    }

    private func redactedAIErrorDescription(_ error: Error) -> String {
        let key = aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return error.localizedDescription }
        return error.localizedDescription.replacingOccurrences(of: key, with: "••••")
    }

    func choosePDFExportDestination(for requestedFile: URL? = nil) {
        if let requestedFile,
           requestedFile.standardizedFileURL != currentFile?.standardizedFileURL {
            guard confirmDocumentTransition() else { return }
            loadFile(requestedFile)
            guard currentFile?.standardizedFileURL == requestedFile.standardizedFileURL else { return }
        }
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

    func chooseImageForInsertion() {
        guard currentFile != nil else {
            errorMessage = text("Open or create a Markdown document before importing images.")
            return
        }

        let panel = NSOpenPanel()
        panel.title = text("Upload Image")
        panel.prompt = text("Upload")
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentFile?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importImageFile(url)
    }

    @discardableResult
    func importImageFile(_ source: URL) -> Bool {
        guard Self.isImageFile(source) else {
            errorMessage = text("Choose an image file.")
            return false
        }
        let securityAccess = source.startAccessingSecurityScopedResource()
        defer {
            if securityAccess { source.stopAccessingSecurityScopedResource() }
        }
        do {
            let byteCount = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard byteCount <= 25 * 1024 * 1024 else {
                errorMessage = text("Images larger than 25 MB are not supported.")
                return false
            }
            let data = try Data(contentsOf: source)
            return importImageData(
                data,
                suggestedFilename: source.lastPathComponent,
                mimeType: UTType(filenameExtension: source.pathExtension)?.preferredMIMEType
            )
        } catch {
            errorMessage = localizedFormat("Markv could not import the image: %@", error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func importImageData(
        _ data: Data,
        suggestedFilename: String?,
        mimeType: String?
    ) -> Bool {
        guard let currentFile else {
            errorMessage = text("Open or create a Markdown document before importing images.")
            return false
        }
        guard data.count <= 25 * 1024 * 1024 else {
            errorMessage = text("Images larger than 25 MB are not supported.")
            return false
        }

        let type = mimeType.flatMap {
            UTType(tag: $0, tagClass: .mimeType, conformingTo: .image)
        }
        let fallbackExtension = type?.preferredFilenameExtension ?? "png"
        let proposed = sanitizedImageFilename(suggestedFilename, fallbackExtension: fallbackExtension)

        do {
            let imageDirectory = currentFile.deletingLastPathComponent()
                .appendingPathComponent("IMG", isDirectory: true)
            try FileManager.default.createDirectory(
                at: imageDirectory,
                withIntermediateDirectories: true
            )
            let destination = uniqueImageDestination(in: imageDirectory, filename: proposed)
            try data.write(to: destination, options: .atomic)
            let encodedName = destination.lastPathComponent.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.urlPathAllowed
            ) ?? destination.lastPathComponent
            performEditorAction(.insertImage("IMG/\(encodedName)"))
            return true
        } catch {
            errorMessage = localizedFormat("Markv could not import the image: %@", error.localizedDescription)
            return false
        }
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

    func createEmptyDocument() {
        guard confirmDocumentTransition() else { return }

        let panel = NSSavePanel()
        panel.title = text("New Document")
        panel.prompt = text("Create")
        panel.nameFieldStringValue = text("Untitled") + ".md"
        panel.directoryURL = currentFolder
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        createEmptyDocument(at: url)
    }

    @discardableResult
    func createEmptyDocument(at requestedURL: URL) -> Bool {
        var url = requestedURL
        if url.pathExtension.isEmpty {
            url.appendPathExtension("md")
        }
        guard Self.isMarkdownFile(url) else {
            errorMessage = text("The document must be saved as a Markdown file.")
            return false
        }

        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            let parent = url.deletingLastPathComponent()
            currentFolder = parent
            defaults.set(parent.path, forKey: Keys.lastFolder)
            refreshFiles()
            loadFile(url)
            return true
        } catch {
            errorMessage = localizedFormat("Markv could not create the document: %@", error.localizedDescription)
            return false
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

    private func sanitizedImageFilename(
        _ suggestedFilename: String?,
        fallbackExtension: String
    ) -> String {
        var filename = suggestedFilename.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        filename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty {
            filename = "image.\(fallbackExtension)"
        } else if URL(fileURLWithPath: filename).pathExtension.isEmpty {
            filename += ".\(fallbackExtension)"
        }
        return filename
    }

    private func uniqueImageDestination(in directory: URL, filename: String) -> URL {
        let original = URL(fileURLWithPath: filename)
        let base = original.deletingPathExtension().lastPathComponent
        let fileExtension = original.pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = fileExtension.isEmpty
                ? "\(base)-\(suffix)"
                : "\(base)-\(suffix).\(fileExtension)"
            candidate = directory.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
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
