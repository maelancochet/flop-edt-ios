import Foundation

/// L'alimentation de l'écran « salles libres ».
///
/// Deux tables ne changent jamais en cours d'année et sont mises de côté d'un
/// appel sur l'autre : les salles d'un département, et son barème de durées de
/// cours. Les cours et les indisponibilités, eux, sont toujours retéléchargés :
/// une salle libérée il y a dix minutes doit apparaître comme libre, ce qui est
/// tout l'intérêt de l'écran.
///
/// **Tous les départements sont interrogés, pas seulement celui de
/// l'utilisateur.** Les salles de l'IUT sont partagées — un TD de CS occupe une
/// salle que la table d'INFO déclare aussi — et ne regarder que son propre
/// département revient à annoncer libres des salles prises. Les requêtes
/// partent en parallèle, donc le coût est celui de la plus lente, pas leur
/// somme : mesuré, on passe d'environ 1,9 s à 2,1 s.
public actor RoomStore {
    private let client: FlopAPIClient
    private var roomTables: [String: [Room]] = [:]
    private var durationTables: [String: [String: Int]] = [:]

    public init(client: FlopAPIClient = FlopAPIClient()) {
        self.client = client
    }

    /// La table des salles du département, mémorisée après le premier appel.
    public func rooms(for department: String) async throws -> [Room] {
        if let known = roomTables[department] { return known }
        let fetched = try await client.send(FlopEndpoints.rooms(dept: department))
        roomTables[department] = fetched
        return fetched
    }

    /// L'occupation des salles pour une semaine.
    ///
    /// - Parameters:
    ///   - department: le département consulté — celui dont on propose les salles.
    ///   - durations: son barème, déjà chargé par l'app, pour éviter une requête.
    ///   - departments: tous les départements de l'IUT. Ceux qu'on ne parvient
    ///     pas à lire ressortent dans ``RoomOccupancy/missingDepartments``.
    public func occupancy(
        department: String,
        week: ISOWeek,
        durations: [String: Int],
        departments: [String] = []
    ) async throws -> RoomOccupancy {
        durationTables[department] = durations
        let offered = try await rooms(for: department)

        let others = departments.filter { $0 != department }
        guard !others.isEmpty else {
            let own = try await weekData(for: department, week: week)
            return RoomOccupancy(
                offering: offered,
                sources: [
                    RoomOccupancy.Source(
                        department: department,
                        rooms: offered,
                        courses: own.courses,
                        unavailabilities: own.unavailabilities,
                        durations: durations
                    )
                ]
            )
        }

        // Les tables de référence des autres départements, en une salve.
        await warmReferenceTables(for: others)

        // Puis les données de la semaine, en une seconde salve.
        let all = [department] + others
        let tables = referenceTables(for: all)
        let fetched = await fetchWeek(for: all, week: week)

        var sources: [RoomOccupancy.Source] = []
        var missing: [String] = []

        for abbrev in all {
            guard case .success(let data)? = fetched[abbrev], let table = tables[abbrev] else {
                if abbrev == department {
                    // Le département consulté est le seul dont l'échec est
                    // fatal : sans ses cours, il n'y a rien à afficher, et un
                    // écran vide vaut mieux qu'un écran faux.
                    if case .failure(let error)? = fetched[abbrev] { throw error }
                    throw APIError.offline
                }
                missing.append(abbrev)
                continue
            }
            sources.append(
                RoomOccupancy.Source(
                    department: abbrev,
                    rooms: table.rooms,
                    courses: data.courses,
                    unavailabilities: data.unavailabilities,
                    durations: table.durations
                )
            )
        }

        return RoomOccupancy(offering: offered, sources: sources, missingDepartments: missing)
    }

    public func clear() {
        roomTables.removeAll()
        durationTables.removeAll()
    }

    // MARK: Tables de référence

    private struct ReferenceTable: Sendable {
        let rooms: [Room]
        let durations: [String: Int]
    }

    private func referenceTables(for departments: [String]) -> [String: ReferenceTable] {
        var out: [String: ReferenceTable] = [:]
        for abbrev in departments {
            guard let rooms = roomTables[abbrev] else { continue }
            out[abbrev] = ReferenceTable(rooms: rooms, durations: durationTables[abbrev] ?? [:])
        }
        return out
    }

    /// Charge en parallèle les salles et les durées manquantes. Ces deux tables
    /// ne bougent pas de l'année : le coût n'est payé qu'une fois par lancement.
    private func warmReferenceTables(for departments: [String]) async {
        let missing = departments.filter { roomTables[$0] == nil || durationTables[$0] == nil }
        guard !missing.isEmpty else { return }

        let client = self.client
        let loaded = await withTaskGroup(of: (String, [Room]?, [String: Int]?).self) { group in
            for abbrev in missing {
                group.addTask {
                    async let rooms = try? client.send(FlopEndpoints.rooms(dept: abbrev))
                    async let types = try? client.send(FlopEndpoints.courseTypes(dept: abbrev))
                    let durations = await types.map { list in
                        Dictionary(list.map { ($0.name, $0.duration) }, uniquingKeysWith: { first, _ in first })
                    }
                    return (abbrev, await rooms, durations)
                }
            }
            var results: [(String, [Room]?, [String: Int]?)] = []
            for await result in group { results.append(result) }
            return results
        }

        for (abbrev, rooms, durations) in loaded {
            if let rooms { roomTables[abbrev] = rooms }
            if let durations { durationTables[abbrev] = durations }
        }
    }

    // MARK: Données de la semaine

    private struct WeekData: Sendable {
        let courses: [ScheduledCourse]
        let unavailabilities: [RoomUnavailability]
    }

    /// Les cours et indisponibilités d'un département pour la semaine.
    ///
    /// Une indisponibilité manquante ne fait pas échouer l'appel : on afficherait
    /// alors *plus* de salles libres que la réalité, ce qui est moins grave que
    /// de ne rien afficher du tout. Les cours, eux, sont indispensables.
    private static func weekData(
        for department: String,
        week: ISOWeek,
        client: FlopAPIClient
    ) async throws -> WeekData {
        async let courses = client.send(FlopEndpoints.departmentSchedule(dept: department, week: week))
        async let unavailabilities = try? client.send(
            FlopEndpoints.roomUnavailabilities(dept: department, week: week)
        )
        return WeekData(
            courses: try await courses.values,
            unavailabilities: await unavailabilities?.values ?? []
        )
    }

    private func weekData(for department: String, week: ISOWeek) async throws -> WeekData {
        try await Self.weekData(for: department, week: week, client: client)
    }

    /// Les cinq départements de front. L'échec de l'un est conservé tel quel :
    /// s'il s'agit du département consulté, c'est lui qu'il faut remonter à
    /// l'utilisateur, et non un « hors ligne » inventé.
    private func fetchWeek(
        for departments: [String],
        week: ISOWeek
    ) async -> [String: Result<WeekData, APIError>] {
        let client = self.client
        let loaded = await withTaskGroup(of: (String, Result<WeekData, APIError>).self) { group in
            for abbrev in departments {
                group.addTask {
                    do {
                        return (abbrev, .success(
                            try await Self.weekData(for: abbrev, week: week, client: client)
                        ))
                    } catch {
                        return (abbrev, .failure(APIError.wrapping(error)))
                    }
                }
            }
            var results: [(String, Result<WeekData, APIError>)] = []
            for await result in group { results.append(result) }
            return results
        }
        return Dictionary(uniqueKeysWithValues: loaded)
    }
}
