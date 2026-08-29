import Foundation

/// Une requête GET typée par la forme de sa réponse.
///
/// Le type de retour est porté par l'endpoint lui-même, ce qui évite d'avoir à
/// le répéter à l'appel et rend impossible de décoder une réponse dans le
/// mauvais modèle.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public let path: String
    public let query: [String: String]

    public init(path: String, query: [String: String] = [:]) {
        self.path = path
        self.query = query
    }

    public func url(relativeTo base: URL) -> URL? {
        guard var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        if !query.isEmpty {
            // Trié pour que l'URL soit stable, donc utilisable comme clé de cache.
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }
}
