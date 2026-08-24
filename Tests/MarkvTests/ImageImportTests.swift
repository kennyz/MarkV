import Foundation
import Testing
@testable import Markv

@Test @MainActor func editorImageBridgeDecodesBase64Metadata() throws {
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    let payload = try #require(MarkdownWebView.imagePayload(from: [
        "base64": bytes.base64EncodedString(),
        "name": "pasted.png",
        "mimeType": "image/png"
    ]))

    #expect(payload.data == bytes)
    #expect(payload.suggestedFilename == "pasted.png")
    #expect(payload.mimeType == "image/png")
}

@Test @MainActor func editorShellHandlesImagePasteAndDropWithoutDataURLs() {
    let shell = MarkdownWebView.documentShell
    #expect(shell.contains("editor.addEventListener('paste'"))
    #expect(shell.contains("editor.addEventListener('drop'"))
    #expect(shell.contains("maximumImportedImageBytes"))
    #expect(shell.contains("messageHandlers.imageImported"))
    #expect(shell.contains("case 'insertImage'"))
    #expect(shell.contains("data-markv-src"))
    #expect(shell.contains("markv-image:///"))
    #expect(shell.contains("normalizedMarkdownImageSource"))
}

@Test @MainActor func localImageSchemeResolvesOnlyFilesInsideMarkdownFolder() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let imageDirectory = root.appendingPathComponent("IMG", isDirectory: true)
    try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let image = imageDirectory.appendingPathComponent("sample image.png")
    try Data([1, 2, 3]).write(to: image)
    let handler = LocalImageSchemeHandler(rootURL: root)
    let request = try #require(URL(string: "markv-image:///IMG/sample%20image.png"))
    #expect(handler.resolvedFileURL(for: request) == image.standardizedFileURL)

    let outside = try #require(URL(string: "markv-image:///../outside.png"))
    #expect(handler.resolvedFileURL(for: outside) == nil)
}
