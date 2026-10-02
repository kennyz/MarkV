import SwiftUI

@main
struct MarkvApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 600)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(model.text("New Document…")) {
                    model.createEmptyDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button(model.text("Open File…")) {
                    model.chooseFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(model.text("Open Folder…")) {
                    model.chooseDirectory()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button(model.text("Save")) {
                    model.save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.currentFile == nil || !model.isDirty)

                Divider()

                Button(model.text("Export as PDF…")) {
                    model.choosePDFExportDestination()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.currentFile == nil)
            }

            CommandGroup(before: .sidebar) {
                Button(model.text("Increase Font Size")) { model.increaseFontSize() }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(model.editorFontSize >= AppModel.editorFontSizeRange.upperBound)
                Button(model.text("Decrease Font Size")) { model.decreaseFontSize() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(model.editorFontSize <= AppModel.editorFontSizeRange.lowerBound)
                Button(model.text("Reset Font Size")) { model.resetEditorFontSize() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Toggle(model.text("Focus Mode"), isOn: $model.focusMode)
                    .keyboardShortcut("8", modifiers: [.command, .option])
                Toggle(model.text("Typewriter Mode"), isOn: $model.typewriterMode)
                    .keyboardShortcut("9", modifiers: [.command, .option])
            }

            CommandMenu(model.text("Format")) {
                Button(model.text("Paragraph")) { model.performEditorAction(.paragraph) }
                ForEach(1...6, id: \.self) { level in
                    Button(model.localizedFormat("Heading %d", level)) { model.performEditorAction(.heading(level)) }
                }
                Divider()
                Button(model.text("Bold")) { model.performEditorAction(.bold) }
                    .keyboardShortcut("b", modifiers: .command)
                Button(model.text("Italic")) { model.performEditorAction(.italic) }
                    .keyboardShortcut("i", modifiers: .command)
                Button(model.text("Inline Code")) { model.performEditorAction(.inlineCode) }
                    .keyboardShortcut("`", modifiers: .command)
                Button(model.text("Strikethrough")) { model.performEditorAction(.strike) }
                Divider()
                Button(model.text("Blockquote")) { model.performEditorAction(.quote) }
                Button(model.text("Bullet List")) { model.performEditorAction(.unorderedList) }
                Button(model.text("Numbered List")) { model.performEditorAction(.orderedList) }
                Button(model.text("Task List")) { model.performEditorAction(.taskList) }
                Button(model.text("Code Block")) { model.performEditorAction(.codeBlock) }
                Button(model.text("Insert Link…")) { model.performEditorAction(.link) }
                Button(model.text("Image URL…")) { model.performEditorAction(.image) }
                Button(model.text("Upload Image…")) { model.chooseImageForInsertion() }
                Button(model.text("Insert Table")) { model.performEditorAction(.table) }
                Button(model.text("Horizontal Rule")) { model.performEditorAction(.horizontalRule) }
            }

            CommandMenu(model.text("AI")) {
                ForEach(AIEditAction.allCases) { action in
                    Button(model.text(action.titleKey)) {
                        model.beginAISelectionEdit(action)
                    }
                    .disabled(!model.aiEnabled || model.currentFile == nil)
                }
            }
        }
    }
}
