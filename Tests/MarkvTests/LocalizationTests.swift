import Foundation
import Testing
@testable import Markv

@Test func chineseLocalizationCoversCoreInterfaceAndFormatting() {
    #expect(AppLanguage.english.text("Open Folder") == "Open Folder")
    #expect(AppLanguage.chinese.text("Open Folder") == "打开文件夹")
    #expect(AppLanguage.chinese.text("Start writing…") == "开始写作…")
    #expect(AppLanguage.chinese.text("Resize Outline") == "调整大纲宽度")
    #expect(AppLanguage.chinese.format("Heading %d", 3) == "标题 3")
    #expect(AppLanguage.chinese.format("A file named %@ already exists.", "note.md") == "名为 note.md 的文件已存在。")
}

@Test @MainActor func interfaceLanguagePersistsAcrossModels() {
    let suiteName = "MarkvLanguageTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = AppModel(defaults: defaults, restoreLastFolder: false)
    #expect(first.appLanguage == .english)
    first.appLanguage = .chinese

    let restored = AppModel(defaults: defaults, restoreLastFolder: false)
    #expect(restored.appLanguage == .chinese)
    #expect(restored.text("Save") == "保存")
}

@Test @MainActor func editorShellContainsRuntimeChinesePresentationStrings() {
    let shell = MarkdownWebView.documentShell
    #expect(shell.contains(#"data-language="en""#))
    #expect(shell.contains("开始写作…"))
    #expect(shell.contains("自然地输入 Markdown…"))
    #expect(shell.contains("插入图片网址或相对路径"))
}
