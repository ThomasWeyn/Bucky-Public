import Foundation

struct TextRule: Equatable {
    let trigger: String
    let replacement: String
    static func key(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
    static func vocabulary(_ text: String) -> [TextRule] {
        text.split(separator: "\n").compactMap { line in
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, !pair[0].isEmpty else { return nil }
            return TextRule(trigger: pair[0], replacement: pair[1])
        }
    }
}

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var trigger: String
    var text: String
    var enabled = true
    func validate(among snippets: [Snippet]) throws {
        guard !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              trigger.count <= 100, !trigger.contains(where: \.isNewline),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 10000 else {
            throw TextToolsError.invalidSnippet
        }
        guard !snippets.contains(where: { $0.id != id && TextRule.key($0.trigger) == TextRule.key(trigger) }) else {
            throw TextToolsError.duplicateTrigger
        }
        guard snippets.contains(where: { $0.id == id }) || snippets.count < 200 else { throw TextToolsError.tooManySnippets }
    }
}

enum TextToolsError: LocalizedError {
    case invalidCSV, invalidRow(Int), emptyImport, fileTooLarge, invalidEncoding
    case invalidSnippet, duplicateTrigger, tooManySnippets
    var errorDescription: String? {
        switch self {
        case .invalidCSV: return "The file has an unfinished or misplaced quote. Use a CSV, TSV or plain-text word list."
        case .invalidRow(let row): return "Row \(row) needs one term, or two non-empty columns: heard words and preferred spelling. Keep each entry on one line (up to 512 characters per field)."
        case .emptyImport: return "No vocabulary entries were found."
        case .fileTooLarge: return "Choose a word list smaller than 1 MB with at most 5,000 entries."
        case .invalidEncoding: return "Save the word list as UTF-8 text, CSV or TSV, then try again."
        case .invalidSnippet: return "Use a short, single-line trigger (up to 100 characters) and non-empty text (up to 10,000 characters)."
        case .duplicateTrigger: return "A snippet already uses that trigger. Edit the existing snippet or choose another phrase."
        case .tooManySnippets: return "You can keep up to 200 snippets."
        }
    }
}

struct VocabularyImport: Identifiable {
    let id = UUID()
    let additions: [TextRule]
    let skipped: Int
    static func read(_ url: URL, existing: String) throws -> VocabularyImport {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        guard data.count <= 1024 * 1024 else { throw TextToolsError.fileTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw TextToolsError.invalidEncoding }
        return try parse(text, existing: existing)
    }
    static func parse(_ input: String, existing: String) throws -> VocabularyImport {
        guard input.utf8.count <= 1024 * 1024 else { throw TextToolsError.fileTooLarge }
        let text = input.hasPrefix("\u{FEFF}") ? String(input.dropFirst()) : input
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        var outsideCounts: [Character: Int] = ["\t": 0, ";": 0, ",": 0]
        var insideQuote = false
        for character in firstLine {
            if character == "\"" { insideQuote.toggle() }
            else if !insideQuote, outsideCounts[character] != nil { outsideCounts[character, default: 0] += 1 }
        }
        let separator: Character? = [Character("\t"), ";", ","].first { outsideCounts[$0, default: 0] > 0 }
        let rows: [[String]]
        if let separator { rows = try delimited(text, separator: separator) }
        else {
            rows = text.components(separatedBy: .newlines).map { line in
                line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            }
        }
        var seen = Set(TextRule.vocabulary(existing).map { TextRule.key($0.trigger) })
        var additions: [TextRule] = []
        var skipped = 0
        var count = 0
        for (index, row) in rows.enumerated() {
            let fields = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if fields.allSatisfy(\.isEmpty) { continue }
            if count == 0 {
                let header = fields.map { $0.lowercased() }
                if (header.count == 1 && ["word", "term", "woord"].contains(header[0])) ||
                    (header.count == 2 && ["heard", "spoken", "from", "phrase", "original", "gehoord"].contains(header[0]) && ["replacement", "preferred", "to", "written", "correct", "vervanging", "preferred spelling"].contains(header[1])) {
                    count += 1; continue
                }
            }
            count += 1
            guard count <= 5001 else { throw TextToolsError.fileTooLarge }
            guard (1...2).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.count <= 512 && !$0.contains(where: \.isNewline) }), !fields[0].contains("=") else { throw TextToolsError.invalidRow(index + 1) }
            guard additions.count + skipped < 5000 else { throw TextToolsError.fileTooLarge }
            let rule = TextRule(trigger: fields[0], replacement: fields.count == 1 ? fields[0] : fields[1])
            if seen.insert(TextRule.key(rule.trigger)).inserted { additions.append(rule) }
            else { skipped += 1 }
        }
        guard count > 0, !additions.isEmpty || skipped > 0 else { throw TextToolsError.emptyImport }
        return VocabularyImport(additions: additions, skipped: skipped)
    }
    func applying(to existing: String) -> String {
        let seen = Set(TextRule.vocabulary(existing).map { TextRule.key($0.trigger) })
        let lines = additions.filter { !seen.contains(TextRule.key($0.trigger)) }.map { "\($0.trigger) = \($0.replacement)" }
        guard !lines.isEmpty else { return existing }
        return existing + (existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n") + lines.joined(separator: "\n")
    }
    private static func delimited(_ text: String, separator: Character) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false, index = text.startIndex
        func appendField() { row.append(field); field = ""; closed = false }
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex && text[next] == "\"" { field.append("\""); index = text.index(after: next); continue }
                    quoted = false; closed = true
                } else { field.append(character) }
            } else if character == separator { appendField() }
            else if character == "\n" || character == "\r\n" || character == "\r" {
                appendField(); rows.append(row); row = []
            } else if character == "\"" {
                guard field.isEmpty && !closed else { throw TextToolsError.invalidCSV }
                quoted = true
            } else {
                guard !closed || character == " " else { throw TextToolsError.invalidCSV }
                if !closed { field.append(character) }
            }
            index = next
        }
        guard !quoted else { throw TextToolsError.invalidCSV }
        appendField(); rows.append(row)
        return rows
    }
}

struct TextExpansion {
    static func apply(_ text: String, vocabulary: String, snippets: [Snippet]) -> String {
        // One pass over the original transcript: inserted text cannot trigger
        // another rule or execute an instruction. Snippets win exact collisions.
        var rules: [String: TextRule] = [:]
        for rule in TextRule.vocabulary(vocabulary) where rules[TextRule.key(rule.trigger)] == nil { rules[TextRule.key(rule.trigger)] = rule }
        for snippet in snippets where snippet.enabled && !snippet.trigger.isEmpty {
            rules[TextRule.key(snippet.trigger)] = TextRule(trigger: snippet.trigger, replacement: snippet.text)
        }
        let alternatives = rules.values.sorted { $0.trigger.count > $1.trigger.count }.map { NSRegularExpression.escapedPattern(for: $0.trigger.precomposedStringWithCanonicalMapping) }
        guard !alternatives.isEmpty, let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])(?:" + alternatives.joined(separator: "|") + ")(?![\\p{L}\\p{N}_])", options: .caseInsensitive) else { return text }
        let normalized = text.precomposedStringWithCanonicalMapping
        let original = normalized as NSString
        let output = NSMutableString(string: normalized)
        for match in regex.matches(in: normalized, range: NSRange(location: 0, length: original.length)).reversed() {
            if let rule = rules[TextRule.key(original.substring(with: match.range))] {
                output.replaceCharacters(in: match.range, with: rule.replacement)
            }
        }
        return output as String
    }
}
