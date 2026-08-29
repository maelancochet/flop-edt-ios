import Foundation

/// Le codec partagé par les réponses du serveur, le cache disque et l'instantané
/// embarqué.
///
/// Un seul codec pour les trois, et non un par usage : le cache et l'instantané
/// stockent les réponses de l'API dans leur forme d'origine (`snake_case`), donc
/// ce qui décode l'une décode les autres. Un instantané qui vieillit mal se
/// détecterait à la compilation, pas à l'exécution.
public enum FlopJSON {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
