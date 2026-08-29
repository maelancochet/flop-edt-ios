import Foundation
import Testing
@testable import FlopEDTKit

extension StubbedNetwork {
    @Suite("Client HTTP")
    struct APIClientTests {

        private func fresh() -> FlopAPIClient {
            StubURLProtocol.reset()
            return StubURLProtocol.makeClient()
        }

        @Test("Une réponse correcte est décodée")
        func decodesSuccess() async throws {
            let client = fresh()
            try StubURLProtocol.stub("alldepts", fixture: "departments")

            let departments = try await client.send(FlopEndpoints.departments)
            #expect(departments.map(\.abbrev) == ["INFO", "CS", "GIM", "RT", "LPMA"])
        }

        /// Le serveur explique souvent ce qui cloche. Ce message doit remonter tel
        /// quel plutôt que d'être remplacé par un « erreur 400 » opaque.
        @Test("Le message d'erreur du serveur est conservé")
        func surfacesServerDetail() async {
            let client = fresh()
            StubURLProtocol.stub(
                "scheduledcourses",
                json: #"{"detail":"A training programme should be given when a group name is given"}"#,
                status: 400
            )

            let endpoint = Endpoint<[ScheduledCourse]>(path: "fetch/scheduledcourses/", query: ["dept": "INFO"])
            await #expect(throws: APIError.http(
                status: 400,
                detail: "A training programme should be given when a group name is given"
            )) {
                try await client.send(endpoint)
            }
        }

        /// Plusieurs endpoints répondent 302 vers la page de login quand on les
        /// filtre mal. Suivre la redirection donnerait du HTML à décoder et une
        /// erreur incompréhensible.
        @Test("Une redirection vers le login n'est pas suivie")
        func doesNotFollowRedirects() async {
            let client = fresh()
            StubURLProtocol.stub("timesettings", StubURLProtocol.Stub(
                status: 302,
                body: Data(),
                contentType: nil,
                location: "https://flopedt.iut-blagnac.fr/?next=/fr/api/base/timesettings/"
            ))

            await #expect(throws: APIError.http(status: 302, detail: nil)) {
                try await client.send(FlopEndpoints.timeSettings)
            }
            // Une seule requête : la redirection n'a pas été suivie.
            #expect(StubURLProtocol.totalRequests == 1)
        }

        @Test("Du HTML est signalé comme tel, pas comme une erreur de décodage")
        func rejectsNonJSON() async {
            let client = fresh()
            StubURLProtocol.stub("alldepts", StubURLProtocol.Stub(
                body: Data("<form method=\"post\">".utf8),
                contentType: "text/html; charset=utf-8"
            ))

            await #expect(throws: APIError.notJSON(contentType: "text/html; charset=utf-8")) {
                try await client.send(FlopEndpoints.departments)
            }
        }

        @Test("Une réponse illisible remonte une erreur de décodage")
        func reportsDecodingFailure() async {
            let client = fresh()
            StubURLProtocol.stub("alldepts", json: #"[{"identifiant":1}]"#)

            await #expect(throws: APIError.self) {
                try await client.send(FlopEndpoints.departments)
            }
        }

        @Test("Les erreurs transitoires sont réessayées, les autres non")
        func retryPolicy() async throws {
            StubURLProtocol.reset()
            let client = StubURLProtocol.makeClient(maxAttempts: 3)
            StubURLProtocol.stub("alldepts", StubURLProtocol.Stub(status: 503, body: Data("{}".utf8)))

            await #expect(throws: APIError.self) {
                try await client.send(FlopEndpoints.departments)
            }
            #expect(StubURLProtocol.requestCount("alldepts") == 3)

            // Un 404 est définitif : réessayer ne sert à rien.
            StubURLProtocol.reset()
            StubURLProtocol.stub("alldepts", StubURLProtocol.Stub(status: 404, body: Data("{}".utf8)))
            await #expect(throws: APIError.self) {
                try await client.send(FlopEndpoints.departments)
            }
            #expect(StubURLProtocol.requestCount("alldepts") == 1)
        }

        @Test("Une coupure réseau est reconnue")
        func offlineIsRecognised() async {
            let client = fresh()
            StubURLProtocol.stub("alldepts", StubURLProtocol.Stub(error: URLError(.notConnectedToInternet)))

            await #expect(throws: APIError.offline) {
                try await client.send(FlopEndpoints.departments)
            }
        }

        @Test("Les erreurs réessayables sont correctement classées")
        func retryClassification() {
            #expect(APIError.offline.isRetryable)
            #expect(APIError.timedOut.isRetryable)
            #expect(APIError.http(status: 503, detail: nil).isRetryable)
            #expect(APIError.http(status: 429, detail: nil).isRetryable)
            #expect(!APIError.http(status: 404, detail: nil).isRetryable)
            #expect(!APIError.notJSON(contentType: nil).isRetryable)
            #expect(!APIError.decoding("").isRetryable)
        }
    }

}
