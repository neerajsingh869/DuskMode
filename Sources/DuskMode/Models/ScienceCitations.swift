import Foundation

/// Mirrors research/citations.json (copied into the app bundle by build.sh) — the
/// Science tab reads this directly rather than hardcoding any study in Swift, so the
/// citations stay in one place (rule: every feature must trace to research/citations.json).
struct CitationsDatabase: Decodable {
    let topics: [Topic]

    struct Topic: Decodable {
        let title: String
        let summary: String
        let implementationImpact: String
        let effectStrength: String
        let citations: [Citation]
    }

    struct Citation: Decodable {
        let title: String
        let authors: String
        let journal: String
        let year: Int
        let keyFinding: String
        let link: String
    }

    static func load() -> CitationsDatabase? {
        guard let url = Bundle.main.url(forResource: "citations", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CitationsDatabase.self, from: data)
    }
}
