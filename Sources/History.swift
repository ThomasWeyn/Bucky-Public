import Foundation

struct Recent: Identifiable, Codable, Equatable {
    var id = UUID()
    let text: String
    var date = Date()
    var duration: Double = 0
    var application: String = "Bucky"
    var words: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}

struct HistoryStore {
    let url: URL
    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Bucky/history.json")) { self.url = url }
    func retained(_ entries: [Recent], now: Date = Date()) -> [Recent] {
        Array(entries.filter { $0.date >= now.addingTimeInterval(-30 * 86400) }.sorted { $0.date > $1.date }.prefix(500))
    }
    func load() throws -> [Recent] {
        guard FileManager.default.fileExists(atPath:url.path) else { return [] }
        return retained(try JSONDecoder().decode([Recent].self, from:Data(contentsOf:url)))
    }
    func save(_ entries: [Recent]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let data = try JSONEncoder().encode(retained(entries))
        try data.write(to:url,options:[.atomic])
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}
