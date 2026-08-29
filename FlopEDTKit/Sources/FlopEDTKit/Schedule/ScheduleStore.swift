import Foundation

/// L'accès à l'emploi du temps : cache, réseau, préchargement, détection de
/// changement.
///
/// La règle de fraîcheur tient en une phrase : **le cache sert à ne jamais
/// montrer d'écran vide, jamais à éviter une requête.** C'est ce qui distingue
/// l'app des flux iCal des enseignants, qui ne se rafraîchissent qu'une fois par
/// jour alors qu'un cours peut être déplacé d'une heure à l'autre.
///
/// Concrètement, ``load(_:)`` rend d'abord ce qu'il a, puis va interroger le
/// serveur. Mesures à l'appui, s'en dispenser ne ferait rien gagner : une
/// semaine filtrée pèse 9,8 Ko pour 0,42 s, alors qu'un simple contrôle de
/// version coûte déjà 0,30 s. Le temps part dans l'aller-retour, pas dans les
/// octets — vérifier avant de télécharger économiserait 0,12 s au prix du
/// risque d'afficher un emploi du temps périmé en le croyant à jour.
///
/// L'unique exception est ``recentEnough`` : une copie que l'app vient
/// elle-même de télécharger, il y a moins de dix secondes, est rendue telle
/// quelle. Ce n'est pas une économie de requête au sens ci-dessus — c'est ne pas
/// redemander deux fois la même chose en dix secondes.
///
/// La version ne sert donc qu'au sondage pendant que l'app est ouverte, où elle
/// devient rentable : 70 octets au lieu de 9,8 Ko, répétés toutes les quelques
/// minutes.
public actor ScheduleStore {
    /// En deçà, une copie en cache est rendue telle quelle, sans interroger le
    /// serveur.
    ///
    /// C'est la seule entorse à la règle « le cache ne sert jamais à éviter une
    /// requête », et elle vise un cas précis : ``prefetch(around:radius:)`` vient
    /// de télécharger la semaine voisine, l'utilisateur y arrive deux secondes
    /// plus tard, et on la redemande au serveur. Le gain de fraîcheur est nul —
    /// le sondage repasse toutes les 120 s — alors que le coût est visible :
    /// deux requêtes au lieu d'une, et un remplacement de l'affichage sous les
    /// yeux de l'utilisateur dès que le serveur bouge entre les deux.
    ///
    /// Dix secondes, c'est le temps de balayer deux ou trois semaines. Au-delà,
    /// on redemande.
    public static let recentEnough: TimeInterval = 10

    private let client: FlopAPIClient
    private let cache: any ScheduleCache
    private let now: @Sendable () -> Date

    public private(set) var selection: ScheduleSelection

    private var memory: [ScheduleCacheKey: WeekSchedule] = [:]
    private var inFlight: [ScheduleCacheKey: Task<WeekSchedule, any Error>] = [:]

    public init(
        selection: ScheduleSelection,
        client: FlopAPIClient = FlopAPIClient(),
        cache: any ScheduleCache,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.selection = selection
        self.client = client
        self.cache = cache
        self.now = now
    }

    // MARK: Sélection

    /// Change d'emploi du temps.
    ///
    /// Vide tout : ce qui était en mémoire concerne un autre groupe, et le
    /// réafficher un instant serait pire qu'un écran de chargement.
    ///
    /// L'app ne passe pas par là : `AppModel.activate(_:)` construit un store
    /// neuf à chaque changement de sélection, ce qui préserve le cache disque
    /// des autres groupes. Cette méthode reste le chemin d'un store réutilisé.
    public func setSelection(_ new: ScheduleSelection) {
        guard new != selection else { return }
        selection = new
        memory.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        cache.removeAll()
    }

    // MARK: Lecture

    private func key(_ week: ISOWeek) -> ScheduleCacheKey {
        ScheduleCacheKey(selection: selection, week: week)
    }

    /// Ce qu'on peut afficher tout de suite, sans réseau.
    public func cached(_ week: ISOWeek) -> WeekSchedule? {
        let key = key(week)
        if let inMemory = memory[key] { return inMemory }
        guard let onDisk = cache.read(key) else { return nil }
        memory[key] = onDisk
        return onDisk
    }

    /// Le cache, et s'il est assez récent pour se passer du serveur.
    ///
    /// Rendu en un seul appel pour ne franchir la frontière de l'acteur qu'une
    /// fois. Un horodatage dans le futur — horloge reculée — n'est pas compté
    /// comme récent.
    private func snapshot(_ week: ISOWeek) -> (schedule: WeekSchedule, isRecent: Bool)? {
        guard let cached = cached(week) else { return nil }
        let age = now().timeIntervalSince(cached.fetchedAt)
        return (cached, age >= 0 && age < Self.recentEnough)
    }

    /// Le geste de lancement : d'abord ce qu'on a, puis ce que dit le serveur.
    ///
    /// La séquence rend au plus deux valeurs. S'il n'y a rien en cache, elle en
    /// rend une seule — mais l'appelant sait alors qu'il doit afficher un
    /// chargement, plutôt que de le deviner.
    public nonisolated func load(_ week: ISOWeek) -> AsyncStream<ScheduleLoad> {
        AsyncStream { continuation in
            let task = Task {
                if let (cached, isRecent) = await self.snapshot(week) {
                    guard !isRecent else {
                        // Téléchargée à l'instant, typiquement par le
                        // préchargement de la semaine voisine : la redemander
                        // ne ferait que remplacer l'affichage par lui-même.
                        continuation.yield(.fresh(cached))
                        continuation.finish()
                        return
                    }
                    continuation.yield(.cached(cached))
                }
                do {
                    continuation.yield(.fresh(try await self.refresh(week)))
                } catch {
                    let failure = APIError.wrapping(error)
                    // Une annulation — écran quitté, groupe changé — n'est pas
                    // une panne : la signaler afficherait un bandeau d'erreur
                    // pour un geste volontaire de l'utilisateur.
                    if !failure.isSilent, !Task.isCancelled {
                        let stale = await self.cached(week)
                        continuation.yield(.failed(failure, stale: stale))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Va chercher la semaine sur le serveur, sans considération de cache.
    ///
    /// Les appels concurrents sur une même semaine partagent la même requête :
    /// le préchargement des semaines voisines et un balayage rapide de
    /// l'utilisateur ne doivent pas doubler le trafic.
    @discardableResult
    public func refresh(_ week: ISOWeek) async throws -> WeekSchedule {
        let key = key(week)
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<WeekSchedule, any Error> { [client, selection, now] in
            let endpoint = FlopEndpoints.schedule(
                dept: selection.department,
                week: week,
                trainProg: selection.promo,
                group: selection.group
            )
            // Les deux requêtes partent ensemble : la version ne coûte donc rien
            // en temps, et le sondage disposera d'une référence dès maintenant.
            async let courses = client.send(endpoint)
            async let info = try? client.send(
                FlopEndpoints.weekInfo(dept: selection.department, week: week)
            )

            let decoded = try await courses
            return WeekSchedule(
                week: week,
                selection: selection,
                courses: decoded.values,
                version: await info?.version,
                fetchedAt: now(),
                unreadableCourses: decoded.skipped
            )
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let schedule = try await task.value
        store(schedule, for: key)
        return schedule
    }

    private func store(_ schedule: WeekSchedule, for key: ScheduleCacheKey) {
        // Une réponse arrivée après un changement de sélection ne doit pas
        // ressusciter l'emploi du temps précédent.
        guard schedule.selection == selection else { return }
        memory[key] = schedule
        cache.write(schedule, for: key)
    }

    // MARK: Préchargement

    /// Précharge les semaines voisines, sans bloquer ni faire remonter d'erreur.
    ///
    /// Un échec est sans conséquence : la semaine sera redemandée si
    /// l'utilisateur s'y rend vraiment.
    public func prefetch(around week: ISOWeek, radius: Int = 1) {
        guard radius > 0 else { return }
        for offset in (-radius...radius) where offset != 0 {
            let neighbour = week.advanced(by: offset)
            guard cached(neighbour) == nil, inFlight[key(neighbour)] == nil else { continue }
            Task { [weak self] in
                _ = try? await self?.refresh(neighbour)
            }
        }
    }

    // MARK: Sondage

    /// Demande au serveur si la semaine a bougé, pour 70 octets.
    ///
    /// À appeler pendant que l'app est au premier plan. Ne retélécharge
    /// l'emploi du temps que si la version a changé.
    public func checkForUpdate(_ week: ISOWeek) async -> UpdateCheck {
        // Rien en cache : il n'y a rien à comparer, et rien à mettre à jour.
        guard let known = cached(week) else { return .indeterminate }

        guard let version = known.version else {
            // `week-infos` avait échoué au chargement de cette semaine. S'en
            // tenir là condamnerait le sondage à ne plus rien faire tant que
            // l'écran reste ouvert : on retélécharge, quitte à payer 9,8 Ko.
            return await reload(week, comparedTo: known)
        }

        guard let info = try? await client.send(
            FlopEndpoints.weekInfo(dept: selection.department, week: week)
        ) else {
            return .indeterminate
        }

        guard info.version != version else { return .unchanged }
        return await reload(week, comparedTo: known)
    }

    /// Retélécharge et compare le contenu, pas les horodatages : le compteur de
    /// version bouge parfois sans que l'emploi du temps change, et annoncer
    /// « mis à jour » sans rien changer à l'écran est déroutant.
    private func reload(_ week: ISOWeek, comparedTo known: WeekSchedule) async -> UpdateCheck {
        guard let updated = try? await refresh(week) else { return .indeterminate }
        return updated.hasSameCourses(as: known) ? .unchanged : .changed(updated)
    }

    // MARK: Divers

    public func clear() {
        memory.removeAll()
        cache.removeAll()
    }
}
