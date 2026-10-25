import Foundation

/// `@AppStorage`-friendly set of hidden built-in book IDs, stored as a JSON-encoded `[String]`.
struct HiddenBookIDs: RawRepresentable, Equatable {
    var ids: Set<String>

    init(ids: Set<String> = []) {
        self.ids = ids
    }

    /// Never fails: empty or undecodable input yields an empty set.
    init?(rawValue: String) {
        if let data = rawValue.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        {
            ids = Set(decoded)
        } else {
            ids = []
        }
    }

    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(ids.sorted()),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }
}
