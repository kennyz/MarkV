import Foundation

struct MarkdownTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let suggestedFilename: String
    let content: String

    static let starter = MarkdownTemplate(
        id: "markdown-starter",
        name: "Markdown Starter",
        summary: "A README-style document with common Markdown blocks.",
        suggestedFilename: "Untitled.md",
        content: """
        # Untitled Document

        A short introduction belongs here. Markv keeps the document readable while you write the Markdown underneath.

        ## Overview

        > Use this space for the one idea readers should remember.

        Add your main points:

        - Keep the structure clear
        - Use **strong text** for emphasis
        - Add [helpful links](https://example.com)

        ## Checklist

        - [ ] Write the first draft
        - [ ] Review the details
        - [ ] Share the finished document

        ## Details

        | Item | Status | Notes |
        | --- | --- | --- |
        | Draft | In progress | Add context here |
        | Review | Pending | Ask for feedback |

        ## Example

        ```swift
        let message = "Hello, Markdown"
        print(message)
        ```

        ---

        _Created with Markv._
        """
    )
}

struct DocumentOutlineItem: Identifiable, Equatable {
    let level: Int
    let title: String
    let anchor: String

    var id: String { anchor }
}

struct DocumentStatistics: Equatable {
    let words: Int
    let characters: Int
    let lines: Int
    let readingMinutes: Int
}

enum DocumentIntelligence {
    static func outline(from markdown: String) -> [DocumentOutlineItem] {
        var inFence = false
        var usedAnchors: [String: Int] = [:]
        var result: [DocumentOutlineItem] = []

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }

            let hashes = trimmed.prefix { $0 == "#" }
            guard (1...6).contains(hashes.count),
                  trimmed.dropFirst(hashes.count).first == " " else { continue }

            let rawTitle = String(trimmed.dropFirst(hashes.count + 1))
                .replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !rawTitle.isEmpty else { continue }

            let base = slug(rawTitle)
            let count = usedAnchors[base, default: 0]
            usedAnchors[base] = count + 1
            let anchor = count == 0 ? base : "\(base)-\(count)"
            result.append(DocumentOutlineItem(level: hashes.count, title: rawTitle, anchor: anchor))
        }
        return result
    }

    static func statistics(for markdown: String) -> DocumentStatistics {
        let characters = markdown.count
        let lines = markdown.isEmpty ? 0 : markdown.components(separatedBy: .newlines).count
        let latinWords = markdown.split { character in
            character.isWhitespace || character.isPunctuation || character.isSymbol
        }.filter { token in
            token.contains { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }.count
        let cjkCharacters = markdown.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }.count
        let words = latinWords + cjkCharacters
        return DocumentStatistics(
            words: words,
            characters: characters,
            lines: lines,
            readingMinutes: words == 0 ? 0 : max(1, Int(ceil(Double(words) / 220.0)))
        )
    }

    static func slug(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar.value > 127 {
                return Character(String(scalar))
            }
            return "-"
        }
        let collapsed = String(allowed)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "section" : collapsed
    }
}
