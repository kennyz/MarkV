import JavaScriptCore
import Testing
@testable import Markv

@Test @MainActor func shortcutDetectorHandlesWebKitWhitespaceAndIMEArtifacts() throws {
    let context = try #require(JSContext())
    context.evaluateScript(MarkdownWebView.shortcutDetectorJavaScript)
    let detector = try #require(context.objectForKeyedSubscript("markvDetectShortcut"))
    let taskDetector = try #require(context.objectForKeyedSubscript("markvDetectTaskItem"))

    func detect(_ value: String) throws -> [String: Any] {
        let result = try #require(detector.call(withArguments: [value]))
        return try #require(result.toDictionary() as? [String: Any])
    }

    #expect(try detect("#\u{00A0}\u{200B}")["type"] as? String == "heading")
    #expect(try detect(">\u{202F}")["type"] as? String == "quote")
    #expect(try detect("- \u{2060}")["type"] as? String == "unordered")
    #expect(try detect("1.\u{00A0}")["type"] as? String == "ordered")
    #expect(try detect("- [ ]\u{00A0}")["type"] as? String == "task")
    #expect(try detect("```swift\u{200B}")["language"] as? String == "swift")
    #expect(taskDetector.call(withArguments: ["[ ]\u{00A0}\u{200B}"]).toDictionary() != nil)
    #expect(taskDetector.call(withArguments: ["[x] "]).objectForKeyedSubscript("checked").toBool())
}

@Test @MainActor func shortcutDetectorDoesNotConvertOrdinaryText() throws {
    let context = try #require(JSContext())
    context.evaluateScript(MarkdownWebView.shortcutDetectorJavaScript)
    let detector = try #require(context.objectForKeyedSubscript("markvDetectShortcut"))

    #expect(detector.call(withArguments: ["# heading already has text"]).isNull)
    #expect(detector.call(withArguments: ["2026. "]).isNull)
}
