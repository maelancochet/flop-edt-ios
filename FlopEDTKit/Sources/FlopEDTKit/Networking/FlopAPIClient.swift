import Foundation

/// Le client HTTP de l'application.
///
/// Deux partis pris tiennent à la raison d'être de l'app — être plus à jour que
/// les flux iCal des enseignants :
///
/// 1. **Le cache URL est désactivé.** La fraîcheur est gérée explicitement par la
///    couche au-dessus, qui affiche d'abord son cache disque puis remplace par
///    ce que renvoie le réseau. Un `URLCache` implicite par-dessus rendrait le
///    comportement imprévisible.
/// 2. **Les redirections ne sont pas suivies.** Plusieurs endpoints répondent 302
///    vers la page de login quand on les filtre mal. Suivre la redirection
///    donnerait du HTML à décoder et une erreur incompréhensible ; on préfère
///    remonter le 302 tel quel.
public struct FlopAPIClient: Sendable {
    public static let blagnac = URL(string: "https://flopedt.iut-blagnac.fr/fr/api/")!

    private let baseURL: URL
    private let session: URLSession
    private let maxAttempts: Int

    public init(
        baseURL: URL = FlopAPIClient.blagnac,
        session: URLSession = FlopAPIClient.makeSession(),
        maxAttempts: Int = 3
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maxAttempts = max(1, maxAttempts)
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        // 15 s ne suffisent plus. Mesuré le 29/08/2026 sur la prod : une semaine
        // complète de département met 15 à 19 s (contre 1,9 s relevées le
        // 31/07), et une semaine filtrée 2,8 à 3,5 s (contre 0,42 s). Un délai
        // plus court que la latence réelle du serveur ne protège de rien : il
        // transforme une réponse lente en échec certain, que les tentatives
        // suivantes ne font qu'allonger.
        //
        // Ces délais comptent l'inactivité, pas la durée totale : un endpoint
        // rapide continue de répondre vite.
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    /// Exécute la requête, avec quelques tentatives sur les erreurs transitoires.
    public func send<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
        var lastError: APIError = .badURL

        for attempt in 0..<maxAttempts {
            do throws(APIError) {
                return try await perform(endpoint)
            } catch {
                lastError = error
                guard error.isRetryable, attempt < maxAttempts - 1 else { throw error }
                // 0,5 s puis 1 s. Le serveur répond en 0,4 s en temps normal :
                // inutile d'attendre davantage.
                let delay = UInt64(500_000_000) << UInt64(attempt)
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    // Annulé pendant l'attente : ne pas relancer une requête
                    // dont plus personne ne veut.
                    throw APIError.cancelled
                }
            }
        }
        throw lastError
    }

    private func perform<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
        guard let url = endpoint.url(relativeTo: baseURL) else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectBlocker())
        } catch let error as URLError {
            throw switch error.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .dataNotAllowed, .internationalRoamingOff:
                APIError.offline
            case .timedOut:
                APIError.timedOut
            case .cancelled:
                // `URLSession` signale une annulation par une `URLError`, pas
                // par `CancellationError` : sans ce cas, un changement de
                // groupe se traduisait par « erreur -999 » à l'écran.
                APIError.cancelled
            default:
                // Hôte injoignable, DNS, TLS : la couche transport a échoué.
                // Ces codes sont négatifs, les ranger dans `http` les faisait
                // passer pour définitifs alors qu'ils valent d'être réessayés.
                APIError.transport(code: error.code.rawValue, detail: error.localizedDescription)
            }
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(code: -1, detail: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.notJSON(contentType: nil)
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, detail: Self.detail(from: data))
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        guard contentType?.contains("json") ?? false else {
            throw APIError.notJSON(contentType: contentType)
        }

        do {
            return try FlopJSON.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Le message d'erreur du serveur, quand il en renvoie un.
    private static func detail(from data: Data) -> String? {
        struct Payload: Decodable { let detail: String }
        return try? JSONDecoder().decode(Payload.self, from: data).detail
    }
}

/// Interrompt les redirections pour qu'un 302 vers la page de login remonte tel
/// quel au lieu d'être suivi et de produire du HTML.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
