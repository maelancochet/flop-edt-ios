import Foundation

/// Ce qu'a donné une tentative de rafraîchissement en tâche de fond.
///
/// Un enum plutôt qu'une erreur levée : au démarrage, l'échec du réseau est un
/// cas normal et non une exception. L'app affiche ce qu'elle a et signale
/// discrètement, elle ne s'arrête pas.
public enum RefreshOutcome: Sendable, Equatable {
    case upToDate
    case updated
    case failed(APIError)

    public var didUpdate: Bool { self == .updated }
}

/// Le chargement du référentiel : disque, instantané embarqué, réseau.
///
/// Ordre de résolution au démarrage :
/// 1. le cache disque, écrit au dernier lancement ;
/// 2. à défaut, l'instantané livré dans l'app ;
/// 3. le réseau, qui vient corriger les deux — sans jamais bloquer l'affichage
///    tant qu'une des deux premières sources a répondu.
///
/// C'est ce qui permet à une première installation de fonctionner même si le
/// serveur de l'IUT est indisponible ce jour-là.
public actor ReferentialLoader {
    /// Le référentiel change au plus une fois par an. Une journée entre deux
    /// revalidations suffit largement — à ne pas confondre avec l'emploi du
    /// temps, qui lui est retéléchargé à chaque lancement.
    public static let defaultMaxAge: TimeInterval = 24 * 60 * 60

    private let client: FlopAPIClient
    private let storage: any ReferentialStorage
    private let bundled: @Sendable () -> Referential?
    private let now: @Sendable () -> Date

    private var loadedLocal = false
    private var inFlight: [String: Task<DepartmentReferential, any Error>] = [:]

    public private(set) var referential = Referential()

    public init(
        client: FlopAPIClient = FlopAPIClient(),
        storage: any ReferentialStorage,
        bundled: @escaping @Sendable () -> Referential? = { BundledReferential.load() },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.client = client
        self.storage = storage
        self.bundled = bundled
        self.now = now
    }

    /// Y a-t-il de quoi afficher un écran sans attendre le réseau ?
    public var hasUsableData: Bool { !referential.isEmpty }

    // MARK: Démarrage

    /// Charge la meilleure source locale disponible. Ne touche pas au réseau.
    ///
    /// À appeler en premier au lancement : le résultat est immédiat, et l'app
    /// peut afficher l'écran avant même que la requête réseau soit partie.
    @discardableResult
    public func loadLocal() -> Referential {
        guard !loadedLocal else { return referential }
        loadedLocal = true

        if let stored = try? storage.read(), !stored.isEmpty {
            referential = stored
        } else if let snapshot = bundled(), !snapshot.isEmpty {
            // L'instantané est daté du jour où il a été fabriqué, pas du jour de
            // l'installation : entre les deux il s'écoule le temps de la revue
            // App Store et celui que l'utilisateur met à installer la mise à
            // jour. On le considère donc toujours périmé, pour qu'une première
            // installation aille systématiquement chercher la version du
            // serveur dès qu'elle le peut.
            referential = snapshot.markedAsUnverified()
        }
        return referential
    }

    // MARK: Rafraîchissement

    /// Revalide le socle, et les départements demandés, si l'ensemble a vieilli.
    ///
    /// Ne lève pas : au démarrage, une panne réseau ne doit pas empêcher
    /// l'affichage de ce qu'on a déjà.
    ///
    /// - Parameter departments: les départements à revalider. `nil` reprend tous
    ///   ceux déjà chargés — ce qui, l'instantané embarqué en livrant cinq,
    ///   revenait à en télécharger cinq à chaque lancement. L'app passe le seul
    ///   département suivi.
    public func refreshIfNeeded(
        maxAge: TimeInterval = defaultMaxAge,
        departments: [String]? = nil
    ) async -> RefreshOutcome {
        loadLocal()
        guard referential.isEmpty || referential.isStale(maxAge: maxAge, now: now()) else {
            return .upToDate
        }
        return await refresh(departments: departments)
    }

    /// Revalide sans condition d'âge.
    ///
    /// C'est ce que déclenche le bouton des réglages. Passer par
    /// ``refreshIfNeeded(maxAge:departments:)`` ne marchait pas : le référentiel
    /// venant d'être revalidé au lancement, le garde de fraîcheur court-circuitait
    /// et le bouton ne lançait aucune requête.
    @discardableResult
    public func forceRefresh(departments: [String] = []) async -> RefreshOutcome {
        loadLocal()
        return await refresh(departments: departments)
    }

    private func refresh(departments: [String]?) async -> RefreshOutcome {
        do {
            try await refreshBase()
            // Seuls les départements demandés : inutile de télécharger GIM pour
            // un étudiant d'INFO.
            for abbrev in departments ?? Array(referential.departmentData.keys) {
                _ = try? await refreshDepartment(abbrev)
            }
            return .updated
        } catch let error as APIError {
            return .failed(error)
        } catch {
            return .failed(.transport(code: -1, detail: error.localizedDescription))
        }
    }

    /// Recharge départements et horaires depuis le serveur.
    @discardableResult
    public func refreshBase() async throws -> Referential {
        loadLocal()

        // Requêtes indépendantes : autant les mener de front.
        async let departments = client.send(FlopEndpoints.departments)
        async let timeSettings = client.send(FlopEndpoints.timeSettings)
        // Le serveur ignorant `?dept=`, une seule requête couvre tous les
        // départements — elle a donc sa place dans le socle.
        async let groupTypes = try? client.send(FlopEndpoints.groupTypes)

        let base = Referential(
            departments: try await departments,
            timeSettings: try await timeSettings,
            groupTypes: await groupTypes ?? [],
            fetchedAt: now()
        )

        referential = referential.merging(base: base)
        persist()
        return referential
    }

    // MARK: Départements

    /// Les données d'un département, du cache si elles sont fraîches, du réseau
    /// sinon.
    ///
    /// Si le réseau échoue alors qu'on a une version périmée, on rend la version
    /// périmée : un arbre de groupes de l'an dernier vaut mieux qu'un écran vide,
    /// et il sera corrigé au prochain rafraîchissement réussi.
    @discardableResult
    public func department(
        _ abbrev: String,
        maxAge: TimeInterval = defaultMaxAge
    ) async throws -> DepartmentReferential {
        loadLocal()

        let cached = referential.data(forDepartment: abbrev)
        if let cached, !cached.isStale(maxAge: maxAge, now: now()) {
            return cached
        }

        do {
            return try await refreshDepartment(abbrev)
        } catch {
            if let cached { return cached }
            throw error
        }
    }

    /// Force le rechargement d'un département.
    ///
    /// Les appels concurrents sur un même département partagent la même requête :
    /// l'écran de sélection peut demander deux fois de suite sans doubler le trafic.
    @discardableResult
    public func refreshDepartment(_ abbrev: String) async throws -> DepartmentReferential {
        if let existing = inFlight[abbrev] {
            return try await existing.value
        }

        let task = Task<DepartmentReferential, any Error> { [client, now] in
            // Trois requêtes indépendantes, menées de front : environ un
            // aller-retour au lieu de trois.
            async let programs = client.send(FlopEndpoints.trainingPrograms(dept: abbrev))
            async let tree = client.send(FlopEndpoints.groupTree(dept: abbrev))
            async let types = client.send(FlopEndpoints.courseTypes(dept: abbrev))
            // Sert uniquement à nommer les niveaux : son absence ne doit pas
            // priver l'utilisateur de l'écran de sélection.
            async let flat = try? client.send(FlopEndpoints.structuralGroups(dept: abbrev))

            return DepartmentReferential(
                trainingPrograms: try await programs,
                groupTree: GroupTree(roots: try await tree),
                courseTypes: try await types,
                structuralGroups: await flat ?? [],
                fetchedAt: now()
            )
        }
        inFlight[abbrev] = task
        defer { inFlight[abbrev] = nil }

        let data = try await task.value
        referential = referential.merging(data, forDepartment: abbrev)
        persist()
        return data
    }

    // MARK: Divers

    public func reset() throws {
        try storage.clear()
        referential = Referential()
        loadedLocal = false
    }

    private func persist() {
        // L'échec d'écriture n'est pas fatal : l'app tourne, elle repartira du
        // réseau au prochain lancement.
        try? storage.write(referential)
    }
}
