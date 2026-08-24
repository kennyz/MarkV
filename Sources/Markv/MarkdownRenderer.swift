import Foundation

enum MarkdownRenderer {
    static func render(_ markdown: String) -> String {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var output: [String] = []
        var index = 0
        var headingAnchors: [String: Int] = [:]

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                let languageClass = language.isEmpty ? "" : " class=\"language-\(escapeAttribute(language))\""
                output.append("<pre><code\(languageClass)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }

            if let heading = heading(from: trimmed) {
                let base = DocumentIntelligence.slug(heading.text)
                let count = headingAnchors[base, default: 0]
                headingAnchors[base] = count + 1
                let anchor = count == 0 ? base : "\(base)-\(count)"
                output.append("<h\(heading.level) id=\"\(escapeAttribute(anchor))\">\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                output.append("<hr>")
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoted.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                output.append("<blockquote>\(render(quoted.joined(separator: "\n")))</blockquote>")
                continue
            }

            if let item = listItem(from: trimmed) {
                let tag = item.ordered ? "ol" : "ul"
                var items: [String] = []
                var containsTasks = false
                while index < lines.count,
                      let next = listItem(from: lines[index].trimmingCharacters(in: .whitespaces)),
                      next.ordered == item.ordered {
                    if let task = taskItem(from: next.text) {
                        containsTasks = true
                        let checked = task.checked ? " checked" : ""
                        items.append("<li class=\"task-item\"><input type=\"checkbox\"\(checked)> \(renderInline(task.text))</li>")
                    } else {
                        items.append("<li>\(renderInline(next.text))</li>")
                    }
                    index += 1
                }
                let listClass = containsTasks ? " class=\"task-list\"" : ""
                output.append("<\(tag)\(listClass)>\(items.joined())</\(tag)>")
                continue
            }

            if index + 1 < lines.count,
               isTableHeader(line: line, delimiter: lines[index + 1]) {
                let headers = tableCells(line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let candidate = lines[index]
                    guard candidate.contains("|"), !candidate.trimmingCharacters(in: .whitespaces).isEmpty else { break }
                    rows.append(tableCells(candidate))
                    index += 1
                }

                let head = headers.map { "<th>\(renderInline($0))</th>" }.joined()
                let body = rows.map { row in
                    "<tr>" + headers.indices.map { column in
                        let value = column < row.count ? row[column] : ""
                        return "<td>\(renderInline(value))</td>"
                    }.joined() + "</tr>"
                }.joined()
                output.append("<div class=\"table-wrap\"><table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table></div>")
                continue
            }

            var paragraph = [trimmed]
            index += 1
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty || startsBlock(candidate) { break }
                if index + 1 < lines.count, isTableHeader(line: lines[index], delimiter: lines[index + 1]) { break }
                paragraph.append(candidate)
                index += 1
            }
            output.append("<p>\(renderInline(paragraph.joined(separator: " ")))</p>")
        }

        return output.joined(separator: "\n")
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func renderInline(_ source: String) -> String {
        var codeFragments: [String] = []
        var prepared = replacingMatches(in: source, pattern: "`([^`]+)`") { match, original in
            let range = Range(match.range(at: 1), in: original)!
            let token = "MARKVCODETOKEN\(codeFragments.count)END"
            codeFragments.append("<code>\(escape(String(original[range])))</code>")
            return token
        }

        prepared = escape(prepared)
        prepared = replacingMatches(in: prepared, pattern: "!\\[([^\\]]*)\\]\\(([^\\s\\)]+)\\)") { match, original in
            let altRange = Range(match.range(at: 1), in: original)!
            let urlRange = Range(match.range(at: 2), in: original)!
            let alt = String(original[altRange])
            let url = safeDestination(String(original[urlRange]), schemes: ["http", "https", "file", "data"], allowsRelative: true)
            return "<img src=\"\(escapeAttribute(url))\" alt=\"\(escapeAttribute(alt))\">"
        }
        prepared = replacingMatches(in: prepared, pattern: "\\[([^\\]]+)\\]\\(([^\\s\\)]+)\\)") { match, original in
            let textRange = Range(match.range(at: 1), in: original)!
            let urlRange = Range(match.range(at: 2), in: original)!
            let label = String(original[textRange])
            let url = safeDestination(String(original[urlRange]), schemes: ["http", "https", "mailto", "file"], allowsRelative: true)
            return "<a href=\"\(escapeAttribute(url))\">\(label)</a>"
        }
        prepared = replacingMatches(in: prepared, pattern: "\\*\\*(.+?)\\*\\*|__(.+?)__") { match, original in
            let capture = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            return "<strong>\(String(original[Range(capture, in: original)!]))</strong>"
        }
        prepared = replacingMatches(in: prepared, pattern: "~~(.+?)~~") { match, original in
            "<del>\(String(original[Range(match.range(at: 1), in: original)!]))</del>"
        }
        prepared = replacingMatches(in: prepared, pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)|(?<!_)_([^_]+)_(?!_)") { match, original in
            let capture = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            return "<em>\(String(original[Range(capture, in: original)!]))</em>"
        }

        for (index, fragment) in codeFragments.enumerated() {
            prepared = prepared.replacingOccurrences(of: "MARKVCODETOKEN\(index)END", with: fragment)
        }
        return prepared
    }

    private static func safeDestination(_ value: String, schemes: Set<String>, allowsRelative: Bool) -> String {
        let decoded = value.replacingOccurrences(of: "&amp;", with: "&")
        guard let components = URLComponents(string: decoded) else { return "#" }
        if let scheme = components.scheme?.lowercased() {
            return schemes.contains(scheme) ? decoded : "#"
        }
        if allowsRelative, !decoded.contains(":") { return decoded }
        return "#"
    }

    private static func replacingMatches(
        in input: String,
        pattern: String,
        transform: (NSTextCheckingResult, String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        var result = input
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(match, result))
        }
        return result
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return (hashes.count, String(line.dropFirst(hashes.count + 1)))
    }

    private static func listItem(from line: String) -> (ordered: Bool, text: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return (false, String(line.dropFirst(2)))
        }
        guard let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else { return nil }
        return (true, String(line[match.upperBound...]))
    }

    private static func taskItem(from text: String) -> (checked: Bool, text: String)? {
        guard let match = text.range(of: #"^\[([ xX])\]\s+"#, options: .regularExpression) else { return nil }
        let marker = text[text.index(after: text.startIndex)]
        return (marker == "x" || marker == "X", String(text[match.upperBound...]))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        line.range(of: #"^(\*\s*){3,}$|^(-\s*){3,}$|^(_\s*){3,}$"#, options: .regularExpression) != nil
    }

    private static func startsBlock(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix(">") || heading(from: line) != nil
            || listItem(from: line) != nil || isHorizontalRule(line)
    }

    private static func tableCells(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableHeader(line: String, delimiter: String) -> Bool {
        let headers = tableCells(line)
        let delimiters = tableCells(delimiter)
        guard line.contains("|"), headers.count == delimiters.count, !headers.isEmpty else { return false }
        return delimiters.allSatisfy {
            $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }
}
