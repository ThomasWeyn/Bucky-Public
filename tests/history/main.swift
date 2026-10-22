import Foundation
func check(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bucky-history-test-" + UUID().uuidString)
let store = HistoryStore(url:directory.appendingPathComponent("history.json"))
defer { try? FileManager.default.removeItem(at:directory) }
check(try store.load().isEmpty,"Missing history starts empty")
let first = Recent(text:"Goedemorgen. Let's start the meeting.",duration:4,application:"Test editor")
try store.save([first])
check(try store.load() == [first],"Unicode transcript and metadata roundtrip")
let mode = try FileManager.default.attributesOfItem(atPath:store.url.path)[.posixPermissions] as! NSNumber
check(mode.intValue == 0o600,"History must be private to the user")
let old = Recent(text:"Expired",date:Date().addingTimeInterval(-31*86400))
let entries = store.retained([old,first])
check(entries == [first],"Thirty-day retention")
let many = (0..<520).map { Recent(text:"Fixture \($0)",date:Date().addingTimeInterval(-Double($0))) }
check(store.retained(many).count == 500,"Bounded history")
try store.save([])
check(try store.load().isEmpty,"Delete persists")
try store.save([first])
check(try store.load() == [first],"Undo persists")
try Data("broken".utf8).write(to:store.url)
var failed = false
 do { _ = try store.load() } catch { failed = true }
check(failed,"Malformed data must surface an error")
check(try String(contentsOf:store.url,encoding:.utf8) == "broken","Read failure must preserve source")
print("9 history checks passed: roundtrip, permissions, retention, capacity, deletion, undo and corruption")
