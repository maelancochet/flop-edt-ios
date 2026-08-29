import Foundation
@testable import FlopEDTKit

/// Un faux réseau branché sous `URLSession`.
///
/// Intercepter au niveau de `URLProtocol` plutôt que de masquer `FlopAPIClient`
/// derrière un protocole : les tests traversent ainsi le vrai client, donc son
/// traitement des codes HTTP, des réponses non-JSON et des redirections.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int = 200
        var body: Data = Data("[]".utf8)
        var contentType: String? = "application/json"
        var location: String?
        var delay: TimeInterval = 0
        var error: URLError?
    }

    private struct Entry {
        let match: String
        let stub: Stub
    }

    private nonisolated(unsafe) static var entries: [Entry] = []
    private nonisolated(unsafe) static var counts: [String: Int] = [:]
    private static let lock = NSLock()

    static func reset() {
        lock.withLock {
            entries = []
            counts = [:]
        }
    }

    /// `match` est cherché dans l'URL complète, `""` attrapant tout. Les entrées
    /// sont examinées dans l'ordre d'ajout : la plus précise doit être
    /// enregistrée en premier.
    static func stub(_ match: String, _ stub: Stub) {
        lock.withLock { entries.append(Entry(match: match, stub: stub)) }
    }

    /// Toutes les requêtes échouent — pour rejouer un appareil hors ligne.
    static func stubOffline() {
        stub("", Stub(error: URLError(.notConnectedToInternet)))
    }

    static func stub(_ match: String, json: String, status: Int = 200) {
        stub(match, Stub(status: status, body: Data(json.utf8)))
    }

    static func stub(_ match: String, fixture: String) throws {
        stub(match, Stub(body: try TestSupport.fixture(fixture)))
    }

    static func requestCount(_ match: String) -> Int {
        lock.withLock { counts[match] ?? 0 }
    }

    static var totalRequests: Int {
        lock.withLock { counts.values.reduce(0, +) }
    }

    private static func resolve(_ url: URL) -> Stub? {
        lock.withLock {
            // `contains("")` vaut `false` en Swift : le cas attrape-tout doit
            // donc être traité à part.
            let matched = entries.first {
                $0.match.isEmpty || url.absoluteString.contains($0.match)
            }
            guard let entry = matched else { return nil }
            counts[entry.match, default: 0] += 1
            return entry.stub
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.resolve(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        if stub.delay > 0 {
            Thread.sleep(forTimeInterval: stub.delay)
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        var headers: [String: String] = [:]
        if let contentType = stub.contentType { headers["Content-Type"] = contentType }
        if let location = stub.location { headers["Location"] = location }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Un client branché sur ce faux réseau, par ailleurs configuré comme le vrai.
    static func makeClient(maxAttempts: Int = 1) -> FlopAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return FlopAPIClient(session: URLSession(configuration: configuration), maxAttempts: maxAttempts)
    }
}
