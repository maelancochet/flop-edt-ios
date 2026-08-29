import Foundation

public enum APIError: Error, Sendable, Equatable {
    case badURL
    case offline
    case timedOut
    /// La requête a été abandonnée — changement d'écran ou de sélection. Ce
    /// n'est pas une panne : l'app ne doit rien afficher pour ça.
    case cancelled
    /// Panne de la couche transport : hôte introuvable, connexion refusée, DNS.
    /// Distinct de ``http`` : ce n'est pas le serveur qui a répondu, c'est le
    /// réseau qui n'a pas abouti — et cela vaut la peine de réessayer.
    case transport(code: Int, detail: String?)
    /// Statut HTTP hors 2xx. `detail` reprend le message du serveur quand il en
    /// fournit un, par exemple « A training programme should be given… ».
    case http(status: Int, detail: String?)
    /// Le serveur a répondu autre chose que du JSON — typiquement la page de
    /// login, renvoyée en 302 sur les endpoints qui exigent une session.
    case notJSON(contentType: String?)
    case decoding(String)

    public var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .transport: true
        case .http(let status, _): status >= 500 || status == 429
        case .badURL, .cancelled, .notJSON, .decoding: false
        }
    }

    /// Une annulation n'est pas un incident : rien à signaler à l'utilisateur.
    public var isSilent: Bool {
        self == .cancelled
    }
}

extension APIError {
    /// Ramène n'importe quelle erreur au vocabulaire du client.
    public static func wrapping(_ error: any Error) -> APIError {
        if let api = error as? APIError { return api }
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError, url.code == .cancelled { return .cancelled }
        return .transport(code: -1, detail: error.localizedDescription)
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .badURL:
            "Adresse invalide."
        case .offline:
            "Pas de connexion à Internet."
        case .timedOut:
            "Le serveur de l'IUT ne répond pas."
        case .cancelled:
            nil
        case .transport:
            "Le serveur de l'IUT est injoignable."
        case .http(let status, let detail):
            detail ?? "Le serveur a répondu \(status)."
        case .notJSON:
            "Réponse inattendue du serveur."
        case .decoding:
            "Réponse illisible du serveur."
        }
    }
}
