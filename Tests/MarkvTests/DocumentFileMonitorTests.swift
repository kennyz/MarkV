import Foundation
import Testing
@testable import Markv

@MainActor
private func eventually(_ condition: () -> Bool) async throws -> Bool {
    for _ in 0..<50 {
        if condition() { return true }
        try await Task.sleep(for: .milliseconds(100))
    }
    return condition()
}

@MainActor
private func withDocument(
    _ body: (AppModel, URL, URL) async throws -> Void
) async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("live.md")
    try "# Original".write(to: file, atomically: true, encoding: .utf8)
    let suite = "MarkvMonitorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults, restoreLastFolder: false)
    model.openDirectory(folder)
    model.openFile(file)
    try await body(model, file, folder)
}

@Test @MainActor func automaticallyReloadsRepeatedAtomicAndInPlaceWrites() async throws {
    try await withDocument { model, file, _ in
        try "# Atomic update".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await eventually { model.documentText == "# Atomic update" })
        #expect(!model.isDirty)
        #expect(model.files(matching: "Atomic").count == 1)
        #expect(model.preview(for: file) == "Atomic update")
        try "# In-place update".write(to: file, atomically: false, encoding: .utf8)
        #expect(try await eventually { model.documentText == "# In-place update" })
        try "".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await eventually { model.documentText.isEmpty })
        #expect(!model.isDirty)
        #expect(!model.hasExternalChanges)
    }
}

@Test @MainActor func protectsUnsavedEditsAndSavesBothVersions() async throws {
    try await withDocument { model, file, folder in
        model.updateDocument("# My edits")
        try "# Other editor".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await eventually { model.hasExternalChanges })
        #expect(model.documentText == "# My edits")
        #expect(model.isDirty)
        #expect(!model.save())
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Other editor")
        #expect(!model.saveDocumentCopy(to: file))
        let copy = folder.appendingPathComponent("copy.md")
        #expect(model.saveDocumentCopy(to: copy))
        #expect(try String(contentsOf: copy, encoding: .utf8) == "# My edits")
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Other editor")
        #expect(!model.isDirty)
        #expect(!model.hasExternalChanges)
    }
}

@Test @MainActor func saveChecksForExternalChangesBeforeMonitorTick() async throws {
    try await withDocument { model, file, _ in
        model.updateDocument("# My unsaved edits")
        try "# Changed on disk".write(to: file, atomically: true, encoding: .utf8)
        #expect(!model.save())
        #expect(model.hasExternalChanges)
        #expect(model.documentText == "# My unsaved edits")
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Changed on disk")
    }
}

@Test @MainActor func pendingEditorInputIsProtectedAndUndoCanReloadLatest() async throws {
    try await withDocument { model, file, _ in
        model.documentEditingBegan()
        try "# External during typing".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await eventually { model.hasExternalChanges })
        #expect(model.documentText == "# Original")
        model.updateDocument("# Typed locally")
        #expect(model.isDirty)
        #expect(model.documentText == "# Typed locally")
        model.updateDocument("# Original")
        #expect(model.documentText == "# External during typing")
        #expect(!model.isDirty)
        #expect(!model.hasExternalChanges)
    }
}

@Test @MainActor func ownSaveDoesNotReloadOrCreateAConflict() async throws {
    try await withDocument { model, file, _ in
        model.updateDocument("# Saved here")
        #expect(model.save())
        try await Task.sleep(for: .milliseconds(1000))
        #expect(model.documentText == "# Saved here")
        #expect(!model.isDirty)
        #expect(!model.hasExternalChanges)
        try "# New external edit".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await eventually { model.documentText == "# New external edit" })
    }
}

@Test @MainActor func followsRenamesAndStopsWatchingPreviousDocuments() async throws {
    try await withDocument { model, original, folder in
        #expect(model.renameCurrentFile(to: "renamed"))
        let renamed = folder.appendingPathComponent("renamed.md")
        try "# Renamed update".write(to: renamed, atomically: true, encoding: .utf8)
        #expect(try await eventually { model.documentText == "# Renamed update" })
        try "# Different file".write(to: original, atomically: true, encoding: .utf8)
        model.openFile(original)
        try "# Previous document changed".write(to: renamed, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(1000))
        #expect(model.documentText == "# Different file")
        model.openDirectory(folder)
        try "# Closed document changed".write(to: original, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(1000))
        #expect(model.currentFile == nil)
        #expect(model.documentText.isEmpty)
    }
}

@Test @MainActor func retriesTemporaryDeletionAndInvalidUTF8WithoutLosingText() async throws {
    try await withDocument { model, file, _ in
        try Data([0xFF, 0xFE, 0xFF]).write(to: file)
        try await Task.sleep(for: .milliseconds(1000))
        #expect(model.documentText == "# Original")
        try FileManager.default.removeItem(at: file)
        try await Task.sleep(for: .milliseconds(1000))
        #expect(model.documentText == "# Original")
        #expect(model.errorMessage == nil)
        try "# Returned".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await eventually { model.documentText == "# Returned" })
    }
}
