import Foundation
import Testing
@testable import Markv

@Test func markdownExtensionsAreCaseInsensitive() {
    #expect(AppModel.isMarkdownFile(URL(fileURLWithPath: "/tmp/notes.MD")))
    #expect(AppModel.isMarkdownFile(URL(fileURLWithPath: "/tmp/readme.markdown")))
    #expect(!AppModel.isMarkdownFile(URL(fileURLWithPath: "/tmp/notes.txt")))
}

@Test func recentsAreUniqueOrderedAndLimited() {
    let a = URL(fileURLWithPath: "/tmp/a.md")
    let b = URL(fileURLWithPath: "/tmp/b.md")
    let c = URL(fileURLWithPath: "/tmp/c.md")

    #expect(AppModel.normalizedRecents([a, b, a, c], limit: 2) == [a, b])
}

@Test func markdownFilesBuildReadablePreviewsAndSearchFullContent() {
    let file = MarkdownFile(
        url: URL(fileURLWithPath: "/tmp/launch-plan.md"),
        modifiedAt: nil,
        byteCount: nil,
        indexedText: """
        # Launch Plan

        **Markv** keeps writing calm and searchable.
        The second paragraph contains a roadmap keyword.
        """
    )

    #expect(file.preview == "Markv keeps writing calm and searchable. The second paragraph contains a roadmap keyword.")
    #expect(file.matches("launch"))
    #expect(file.matches("ROADMAP"))
    #expect(file.matches("writing searchable"))
    #expect(!file.matches("missing phrase"))
}

@Test @MainActor func opensEditsAndSavesARealMarkdownFile() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let file = folder.appendingPathComponent("note.md")
    try "# Before".write(to: file, atomically: true, encoding: .utf8)
    let suiteName = "MarkvTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AppModel(defaults: defaults, restoreLastFolder: false)
    model.openDirectory(folder)
    #expect(model.files.map(\.name) == ["note.md"])
    #expect(model.files(matching: "Before").map(\.name) == ["note.md"])

    model.openFile(file)
    #expect(model.documentText == "# Before")
    #expect(model.recentFiles.first == file.standardizedFileURL)

    model.updateDocument("# After")
    #expect(model.isDirty)
    #expect(model.save())
    #expect(!model.isDirty)
    #expect(try String(contentsOf: file, encoding: .utf8) == "# After")

    let exportWithoutExtension = folder.appendingPathComponent("note-export")
    model.exportPDF(to: exportWithoutExtension)
    #expect(model.editorCommand?.action == .exportPDF(exportWithoutExtension.appendingPathExtension("pdf")))
}

@Test @MainActor func renamesCurrentFileAndSynchronizesLibraryState() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let original = folder.appendingPathComponent("draft.md")
    try "# Draft\n\nOpening text".write(to: original, atomically: true, encoding: .utf8)
    let suiteName = "MarkvRenameTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AppModel(defaults: defaults, restoreLastFolder: false)
    model.openDirectory(folder)
    model.openFile(original)

    #expect(model.renameCurrentFile(to: "Final Note.md"))
    let renamed = folder.appendingPathComponent("Final Note.md").standardizedFileURL
    #expect(model.currentFile == renamed)
    #expect(model.files.map(\.name) == ["Final Note.md"])
    #expect(model.recentFiles.first == renamed)
    #expect(!FileManager.default.fileExists(atPath: original.path))
    #expect(try String(contentsOf: renamed, encoding: .utf8).contains("Opening text"))

    let collision = folder.appendingPathComponent("taken.md")
    try "occupied".write(to: collision, atomically: true, encoding: .utf8)
    #expect(!model.renameCurrentFile(to: "taken"))
    #expect(model.currentFile == renamed)
    model.appLanguage = .chinese
    #expect(!model.renameCurrentFile(to: "../invalid"))
    #expect(model.errorMessage == "请输入不含路径分隔符的有效文件名。")
}

@Test @MainActor func externalDropOpensFirstValidMarkdownFile() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let textFile = folder.appendingPathComponent("ignore.txt")
    let markdownFile = folder.appendingPathComponent("drop-me.md")
    try "plain".write(to: textFile, atomically: true, encoding: .utf8)
    try "# Dropped".write(to: markdownFile, atomically: true, encoding: .utf8)

    let suiteName = "MarkvDropTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, restoreLastFolder: false)

    #expect(model.openExternalFiles([textFile, markdownFile]))
    #expect(model.currentFile == markdownFile.standardizedFileURL)
    #expect(model.currentFolder == folder.standardizedFileURL)
    #expect(model.documentText == "# Dropped")
}

@Test @MainActor func externalDropRejectsUnsupportedFiles() throws {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).txt")
    try "plain".write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }

    let suiteName = "MarkvDropRejectTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(defaults: defaults, restoreLastFolder: false)

    #expect(!model.openExternalFiles([file]))
    #expect(model.currentFile == nil)
    #expect(model.errorMessage != nil)
}

@Test @MainActor func appearanceThemePersistsAcrossModels() {
    let suiteName = "MarkvThemeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = AppModel(defaults: defaults, restoreLastFolder: false)
    #expect(first.appearanceTheme == .khaki)
    first.appearanceTheme = .white

    let restored = AppModel(defaults: defaults, restoreLastFolder: false)
    #expect(restored.appearanceTheme == .white)
}

@Test func outlineSkipsCodeFencesAndCreatesUniqueAnchors() {
    let markdown = """
    # Hello World
    ## Details
    ```markdown
    # Not a heading
    ```
    ## Details
    ### 中文标题
    """

    #expect(DocumentIntelligence.outline(from: markdown) == [
        DocumentOutlineItem(level: 1, title: "Hello World", anchor: "hello-world"),
        DocumentOutlineItem(level: 2, title: "Details", anchor: "details"),
        DocumentOutlineItem(level: 2, title: "Details", anchor: "details-1"),
        DocumentOutlineItem(level: 3, title: "中文标题", anchor: "中文标题")
    ])
}

@Test func documentStatisticsCountLatinAndCJKContent() {
    let stats = DocumentIntelligence.statistics(for: "Hello world\n你好")
    #expect(stats.words == 4)
    #expect(stats.characters == 14)
    #expect(stats.lines == 2)
    #expect(stats.readingMinutes == 1)
}

@Test func starterTemplateExercisesCommonMarkdownBlocks() {
    let content = MarkdownTemplate.starter.content
    #expect(content.hasPrefix("# Untitled Document"))
    #expect(content.contains("- [ ] Write the first draft"))
    #expect(content.contains("| Item | Status | Notes |"))
    #expect(content.contains("```swift"))
}
