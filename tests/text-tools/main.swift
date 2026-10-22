import Foundation
func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
func rejects(_ message: String, _ block: () throws -> Void) { do { try block(); fatalError(message) } catch {} }
let csv = try VocabularyImport.parse("\u{FEFF}heard,preferred\r\n\"alpha, beta\",\"Alpha; Beta\"\r\n\"say \"\"yes\"\"\",YES\r\n", existing: "alpha = Alpha")
check(csv.additions.count == 2, "Quoted CSV and BOM")
check(csv.additions[0] == TextRule(trigger: "alpha, beta", replacement: "Alpha; Beta"), "Separator inside quoted field")
check(csv.additions[1].trigger == "say \"yes\"", "Escaped quote")
let semicolon = try VocabularyImport.parse("heard;preferred\nalpha;Alpha\nbeta;Beta", existing: "")
check(semicolon.additions.count == 2, "Semicolon CSV")
let tsv = try VocabularyImport.parse("heard\tpreferred\nword\tWord", existing: "")
check(tsv.additions.count == 1, "TSV")
let terms = try VocabularyImport.parse("word\nDelta\nEcho\n", existing: "")
check(terms.additions.map(\.replacement) == ["Delta", "Echo"], "One-column word list")
let merge = try VocabularyImport.parse("heard,preferred\nalpha,CHANGED\nBeta,Beta\nbeta,other", existing: "ALPHA = Alpha\n")
check(merge.additions.count == 1 && merge.skipped == 2, "Existing and duplicate spellings retained")
check(merge.applying(to: "ALPHA = Alpha\n") == "ALPHA = Alpha\nBeta = Beta", "Append only")
check(merge.applying(to: "Beta = Existing") == "Beta = Existing", "Recheck conflicts at apply time")
rejects("Malformed CSV must reject atomically") { _ = try VocabularyImport.parse("heard,preferred\nvalid,Valid\n\"unfinished", existing: "") }
rejects("Empty replacement") { _ = try VocabularyImport.parse("heard,preferred\nalpha,", existing: "") }
rejects("Extra columns") { _ = try VocabularyImport.parse("a,b,c", existing: "") }
rejects("Multiline vocabulary cannot fit line editor") { _ = try VocabularyImport.parse("heard,preferred\na,\"two\nlines\"", existing: "") }
rejects("File bound") { _ = try VocabularyImport.parse(String(repeating: "a", count: 1024 * 1024 + 1), existing: "") }
let snippet = Snippet(trigger: "insert reply", text: "Hello,\n\nThank you. $1 \\ done")
try snippet.validate(among: [])
rejects("Duplicate snippets") { try Snippet(trigger: "INSERT REPLY", text: "Other").validate(among: [snippet]) }
rejects("Empty triggers") { try Snippet(trigger: " ", text: "Other").validate(among: []) }
let text = TextExpansion.apply("INSERT REPLY. alpha, alphabet, _alpha and insert replybook.", vocabulary: "alpha = Alpha\nAlpha = Wrong\ninsert reply = Wrong", snippets: [snippet])
check(text == "Hello,\n\nThank you. $1 \\ done. Alpha, alphabet, _alpha and insert replybook.", "Whole phrases, literal multiline, snippet precedence, no chaining")
let long = Snippet(trigger: "insert long reply", text: "Long")
let short = Snippet(trigger: "insert", text: "Short")
check(TextExpansion.apply("insert long reply", vocabulary: "", snippets: [short, long]) == "Long", "Longest phrase wins")
var disabled = snippet; disabled.enabled = false
check(TextExpansion.apply("insert reply", vocabulary: "", snippets: [disabled]) == "insert reply", "Disabled snippets")
check(TextExpansion.apply("cafe\u{301}", vocabulary: "café = Coffee", snippets: []) == "Coffee", "Unicode canonical equivalence")
let data = try JSONEncoder().encode([snippet, long])
let decoded = try JSONDecoder().decode([Snippet].self, from: data)
check(decoded == [snippet, long], "Snippet persistence roundtrip")
print("Text-tools checks passed: CSV/TSV, import conflicts/errors, literal Unicode expansion, snippets and persistence")
