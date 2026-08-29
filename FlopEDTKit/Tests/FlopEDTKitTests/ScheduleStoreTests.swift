import Foundation
import Testing
@testable import FlopEDTKit

extension StubbedNetwork {
    @Suite("Emploi du temps")
    struct ScheduleStoreTests {

        private static let selection = ScheduleSelection(department: "INFO", promo: "BUT1", group: "1A")
        private static let week = ISOWeek(week: 12, year: 2026)

        private func stubSchedule(version: Int = 270, delay: TimeInterval = 0) throws {
            StubURLProtocol.reset()
            StubURLProtocol.stub("scheduledcourses", StubURLProtocol.Stub(
                body: try TestSupport.fixture("courses-INFO-BUT1-1A"),
                delay: delay
            ))
            StubURLProtocol.stub("week-infos", json: """
                {"version":\(version),"proposed_pref":-1,"required_pref":-1,"regen":"N, 444"}
                """)
        }

        /// Une horloge qu'on fait avancer à la main.
        ///
        /// Le store rend telle quelle une copie de moins de dix secondes : sans
        /// pouvoir franchir cette fenêtre, on ne peut plus tester le
        /// « cache d'abord, réseau ensuite ».
        final class Clock: @unchecked Sendable {
            private let lock = NSLock()
            private var value: Date

            init(_ start: Date = .now) { value = start }

            var now: Date { lock.withLock { value } }

            func advance(_ seconds: TimeInterval) {
                lock.withLock { value = value.addingTimeInterval(seconds) }
            }
        }

        private func store(
            cache: any ScheduleCache,
            selection: ScheduleSelection = selection,
            maxAttempts: Int = 1,
            clock: Clock = Clock()
        ) -> ScheduleStore {
            ScheduleStore(
                selection: selection,
                client: StubURLProtocol.makeClient(maxAttempts: maxAttempts),
                cache: cache,
                now: { clock.now }
            )
        }

        private func collect(_ stream: AsyncStream<ScheduleLoad>) async -> [ScheduleLoad] {
            var result: [ScheduleLoad] = []
            for await value in stream { result.append(value) }
            return result
        }

        // MARK: Fraîcheur

        /// Le comportement au lancement : afficher ce qu'on a sans attendre, puis
        /// remplacer par ce que dit le serveur.
        @Test("Le cache s'affiche d'abord, le réseau ensuite")
        func yieldsCachedThenFresh() async throws {
            try stubSchedule()
            let clock = Clock()
            let subject = store(cache: InMemoryScheduleCache(), clock: clock)

            // Premier passage : rien en cache, une seule valeur.
            let first = await collect(subject.load(Self.week))
            #expect(first.count == 1)
            #expect(first[0].isFresh)

            // Passé la fenêtre de dix secondes, le cache répond d'abord et le
            // réseau confirme.
            clock.advance(60)
            let second = await collect(subject.load(Self.week))
            #expect(second.count == 2)
            if case .cached = second[0] {} else { Issue.record("la première valeur devait venir du cache") }
            #expect(second[1].isFresh)

            // Et le réseau a bien été interrogé les deux fois : passé la
            // fenêtre, le cache ne sert jamais à éviter une requête.
            #expect(StubURLProtocol.requestCount("scheduledcourses") == 2)
        }

        /// L'exception à la règle. `prefetch` télécharge la semaine voisine ;
        /// deux secondes plus tard l'utilisateur y arrive, et la redemander ne
        /// ferait que remplacer l'affichage par lui-même — en le faisant
        /// clignoter dès que le serveur bouge entre les deux requêtes.
        @Test("Une semaine tout juste préchargée n'est pas redemandée")
        func recentCacheSkipsTheNetwork() async throws {
            try stubSchedule()
            let clock = Clock()
            let subject = store(cache: InMemoryScheduleCache(), clock: clock)

            await subject.prefetch(around: Self.week.advanced(by: -1))
            try await Task.sleep(nanoseconds: 300_000_000)
            let afterPrefetch = StubURLProtocol.requestCount("scheduledcourses")
            #expect(afterPrefetch > 0)

            clock.advance(2)
            let values = await collect(subject.load(Self.week))

            // Une seule valeur, donnée comme fraîche, et aucune requête de plus.
            #expect(values.count == 1)
            #expect(values[0].isFresh)
            #expect(values[0].schedule?.courses.count == 22)
            #expect(StubURLProtocol.requestCount("scheduledcourses") == afterPrefetch)
        }

        @Test("Passé dix secondes, la semaine est redemandée")
        func staleCacheGoesBackToTheNetwork() async throws {
            try stubSchedule()
            let clock = Clock()
            let subject = store(cache: InMemoryScheduleCache(), clock: clock)
            _ = try await subject.refresh(Self.week)
            let before = StubURLProtocol.requestCount("scheduledcourses")

            clock.advance(ScheduleStore.recentEnough + 1)
            let values = await collect(subject.load(Self.week))

            #expect(values.count == 2)
            #expect(StubURLProtocol.requestCount("scheduledcourses") == before + 1)
        }

        /// Une entrée relue du disque au lancement porte l'horodatage de la
        /// session précédente : elle ne doit jamais passer pour récente.
        @Test("Une entrée d'une session précédente n'est jamais réputée récente")
        func cacheFromAPreviousSessionIsNotRecent() async throws {
            try stubSchedule()
            let cache = InMemoryScheduleCache()
            let old = WeekSchedule(
                week: Self.week,
                selection: Self.selection,
                courses: [],
                version: 1,
                fetchedAt: Date(timeIntervalSinceNow: -3600)
            )
            cache.write(old, for: ScheduleCacheKey(selection: Self.selection, week: Self.week))

            let subject = store(cache: cache)
            let values = await collect(subject.load(Self.week))

            #expect(values.count == 2)
            #expect(values[1].schedule?.courses.count == 22)
        }

        @Test("Une panne réseau rend quand même le cache, avec l'erreur")
        func failureKeepsStaleData() async throws {
            try stubSchedule()
            let cache = InMemoryScheduleCache()
            let clock = Clock()
            let subject = store(cache: cache, clock: clock)
            _ = try await subject.refresh(Self.week)
            clock.advance(60)

            StubURLProtocol.reset()
            StubURLProtocol.stubOffline()

            let values = await collect(subject.load(Self.week))
            #expect(values.count == 2)
            guard case .failed(let error, let stale) = values[1] else {
                Issue.record("la seconde valeur devait être un échec")
                return
            }
            #expect(error == .offline)
            #expect(stale?.courses.count == 22)
        }

        @Test("Sans cache ni réseau, l'échec est rendu sans données")
        func failureWithoutCache() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.stubOffline()
            let subject = store(cache: InMemoryScheduleCache())

            let values = await collect(subject.load(Self.week))
            #expect(values.count == 1)
            guard case .failed(_, let stale) = values[0] else {
                Issue.record("un échec était attendu")
                return
            }
            #expect(stale == nil)
        }

        /// La version part en même temps que les cours, donc sans coût de temps.
        @Test("La version est relevée en même temps que les cours")
        func capturesVersionAlongsideCourses() async throws {
            try stubSchedule(version: 270)
            let subject = store(cache: InMemoryScheduleCache())

            let schedule = try await subject.refresh(Self.week)
            #expect(schedule.version == 270)
            #expect(schedule.courses.count == 22)
        }

        /// Si `week-infos` échoue, l'emploi du temps doit quand même arriver :
        /// la version n'est qu'un confort pour le sondage.
        @Test("Une version indisponible n'empêche pas de charger la semaine")
        func missingVersionIsNotFatal() async throws {
            StubURLProtocol.reset()
            try StubURLProtocol.stub("scheduledcourses", fixture: "courses-INFO-BUT1-1A")
            StubURLProtocol.stub("week-infos", StubURLProtocol.Stub(status: 500, body: Data("{}".utf8)))

            let subject = store(cache: InMemoryScheduleCache())
            let schedule = try await subject.refresh(Self.week)
            #expect(schedule.courses.count == 22)
            #expect(schedule.version == nil)
        }

        // MARK: Sondage

        @Test("Une version inchangée ne déclenche aucun téléchargement")
        func pollingDetectsNoChange() async throws {
            try stubSchedule(version: 270)
            let subject = store(cache: InMemoryScheduleCache())
            _ = try await subject.refresh(Self.week)

            let before = StubURLProtocol.requestCount("scheduledcourses")
            #expect(await subject.checkForUpdate(Self.week) == .unchanged)
            #expect(StubURLProtocol.requestCount("scheduledcourses") == before)
        }

        /// Le cas qui justifie l'app : un cours déplacé pendant la journée.
        @Test("Une version différente déclenche le rechargement")
        func pollingDetectsChange() async throws {
            try stubSchedule(version: 270)
            let subject = store(cache: InMemoryScheduleCache())
            _ = try await subject.refresh(Self.week)

            // Nouvelle version *et* contenu réellement différent.
            let all = try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-BUT1-1A")
            StubURLProtocol.reset()
            StubURLProtocol.stub("scheduledcourses", StubURLProtocol.Stub(
                body: try FlopJSON.encoder.encode(Array(all.dropFirst()))
            ))
            StubURLProtocol.stub("week-infos", json: #"{"version":271,"proposed_pref":-1,"required_pref":-1,"regen":"N"}"#)

            let outcome = await subject.checkForUpdate(Self.week)
            #expect(outcome.didChange)
            guard case .changed(let updated) = outcome else { return }
            #expect(updated.version == 271)
            #expect(updated.courses.count == all.count - 1)
        }

        /// Le compteur de version bouge parfois sans que l'emploi du temps
        /// change. Annoncer « mis à jour » sans rien changer à l'écran laisse
        /// l'utilisateur chercher ce qui a bougé.
        @Test("Une version qui bouge sans que les cours changent ne se signale pas")
        func pollingIgnoresIdenticalContent() async throws {
            try stubSchedule(version: 270)
            let subject = store(cache: InMemoryScheduleCache())
            _ = try await subject.refresh(Self.week)

            try stubSchedule(version: 271)
            #expect(await subject.checkForUpdate(Self.week) == .unchanged)
        }

        /// Si `week-infos` a échoué au chargement de la semaine, la version est
        /// inconnue. S'en tenir là condamnait le sondage à ne plus rien faire
        /// tant que l'écran restait ouvert — la promesse de fraîcheur
        /// s'éteignait en silence.
        @Test("Sans version connue, le sondage retélécharge au lieu d'abandonner")
        func pollingWithoutVersionStillRefreshes() async throws {
            StubURLProtocol.reset()
            try StubURLProtocol.stub("scheduledcourses", fixture: "courses-INFO-BUT1-1A")
            StubURLProtocol.stub("week-infos", StubURLProtocol.Stub(status: 500, body: Data("{}".utf8)))

            let subject = store(cache: InMemoryScheduleCache())
            let initial = try await subject.refresh(Self.week)
            #expect(initial.version == nil)

            // L'emploi du temps change côté serveur.
            let all = try TestSupport.decode([ScheduledCourse].self, from: "courses-INFO-BUT1-1A")
            StubURLProtocol.reset()
            StubURLProtocol.stub("scheduledcourses", StubURLProtocol.Stub(
                body: try FlopJSON.encoder.encode(Array(all.dropFirst(2)))
            ))
            StubURLProtocol.stub("week-infos", StubURLProtocol.Stub(status: 500, body: Data("{}".utf8)))

            let outcome = await subject.checkForUpdate(Self.week)
            #expect(outcome.didChange)
            guard case .changed(let updated) = outcome else { return }
            #expect(updated.courses.count == all.count - 2)
        }

        @Test("Sans référence de version, le sondage ne conclut pas")
        func pollingWithoutBaseline() async throws {
            try stubSchedule()
            let subject = store(cache: InMemoryScheduleCache())
            #expect(await subject.checkForUpdate(Self.week) == .indeterminate)
        }

        @Test("Un sondage hors ligne ne conclut pas non plus")
        func pollingOffline() async throws {
            try stubSchedule(version: 270)
            let subject = store(cache: InMemoryScheduleCache())
            _ = try await subject.refresh(Self.week)

            StubURLProtocol.reset()
            StubURLProtocol.stubOffline()
            #expect(await subject.checkForUpdate(Self.week) == .indeterminate)
        }

        // MARK: Sélection

        /// Changer de groupe ne doit jamais laisser voir l'emploi du temps du
        /// groupe précédent, même une fraction de seconde.
        @Test("Changer de sélection vide le cache")
        func changingSelectionClearsCache() async throws {
            try stubSchedule()
            let cache = InMemoryScheduleCache()
            let subject = store(cache: cache)
            _ = try await subject.refresh(Self.week)
            #expect(await subject.cached(Self.week) != nil)

            await subject.setSelection(
                ScheduleSelection(department: "INFO", promo: "BUT2", group: "2A")
            )
            #expect(await subject.cached(Self.week) == nil)
        }

        @Test("Reposer la même sélection ne vide rien")
        func samesSelectionIsNoOp() async throws {
            try stubSchedule()
            let subject = store(cache: InMemoryScheduleCache())
            _ = try await subject.refresh(Self.week)

            await subject.setSelection(Self.selection)
            #expect(await subject.cached(Self.week) != nil)
        }

        /// Une réponse partie avant un changement de groupe ne doit pas
        /// ressusciter l'ancien emploi du temps en arrivant après.
        @Test("Une réponse tardive n'écrase pas la nouvelle sélection")
        func lateResponseIsDiscarded() async throws {
            try stubSchedule(delay: 0.3)
            let cache = InMemoryScheduleCache()
            let subject = store(cache: cache)

            let pending = Task { try await subject.refresh(Self.week) }
            try await Task.sleep(nanoseconds: 50_000_000)

            let other = ScheduleSelection(department: "INFO", promo: "BUT2", group: "2A")
            await subject.setSelection(other)
            _ = try? await pending.value

            #expect(await subject.cached(Self.week)?.selection != Self.selection)
        }

        // MARK: Préchargement

        @Test("Les semaines voisines sont préchargées")
        func prefetchesNeighbours() async throws {
            try stubSchedule()
            let subject = store(cache: InMemoryScheduleCache())

            await subject.prefetch(around: Self.week)
            try await Task.sleep(nanoseconds: 300_000_000)

            #expect(await subject.cached(Self.week.advanced(by: -1)) != nil)
            #expect(await subject.cached(Self.week.advanced(by: 1)) != nil)
        }

        @Test("Le préchargement ne retélécharge pas ce qui est déjà là")
        func prefetchSkipsCachedWeeks() async throws {
            try stubSchedule()
            let subject = store(cache: InMemoryScheduleCache())
            _ = try await subject.refresh(Self.week.advanced(by: 1))

            let before = StubURLProtocol.requestCount("scheduledcourses")
            await subject.prefetch(around: Self.week, radius: 1)
            try await Task.sleep(nanoseconds: 300_000_000)

            // Seule la semaine précédente restait à charger.
            #expect(StubURLProtocol.requestCount("scheduledcourses") == before + 1)
        }

        @Test("Deux demandes concurrentes d'une même semaine partagent la requête")
        func concurrentRefreshIsShared() async throws {
            try stubSchedule(delay: 0.2)
            let subject = store(cache: InMemoryScheduleCache())

            async let first = subject.refresh(Self.week)
            async let second = subject.refresh(Self.week)
            let (left, right) = try await (first, second)

            #expect(left == right)
            #expect(StubURLProtocol.requestCount("scheduledcourses") == 1)
        }

        // MARK: Franchissement du nouvel an

        /// Le bout du parcours pour la régression de la v1 : le store doit
        /// demander la semaine 1 de 2026 pour une date de décembre 2025.
        @Test("La semaine du nouvel an est demandée avec l'année ISO")
        func newYearWeekIsRequestedCorrectly() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.stub("week-infos", json: #"{"version":1,"proposed_pref":-1,"required_pref":-1,"regen":"I"}"#)
            // L'URL attendue en entier : c'est `year=2026` qui compte, alors que
            // la date est en décembre 2025.
            let expected = "scheduledcourses/?dept=INFO&group=1A&lineage=true&train_prog=BUT1&week=1&year=2026"
            try StubURLProtocol.stub(expected, fixture: "courses-INFO-BUT1-1A")

            let subject = store(cache: InMemoryScheduleCache())
            let week = ISOWeek(containing: TestSupport.date("2025-12-31"))
            let schedule = try await subject.refresh(week)

            #expect(schedule.courses.count == 22)
            #expect(StubURLProtocol.requestCount(expected) == 1)
        }
    }
}
