import Foundation

public final class FileStore {
    public static let shared = FileStore()
    private init() {}

    public func loadSnapshot(from url: URL) throws -> AppSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.gymForge.decode(AppSnapshot.self, from: data)
    }

    public func save(_ snapshot: AppSnapshot, to url: URL) throws {
        let data = try JSONEncoder.gymForge.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }
}

public extension JSONEncoder {
    static var gymForge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var gymForge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
