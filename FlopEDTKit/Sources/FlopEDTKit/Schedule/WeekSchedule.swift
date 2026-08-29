import Foundation

/// L'emploi du temps d'une semaine, pour une sélection donnée.
public struct WeekSchedule: Codable, Hashable, Sendable {
    public let week: ISOWeek
    public let selection: ScheduleSelection
    public let courses: [ScheduledCourse]
    /// La version annoncée par `/extra/week-infos/`, quand elle a pu être lue.
    /// Sert uniquement à repérer un changement pendant que l'app est ouverte.
    public let version: Int?
    public let fetchedAt: Date
    /// Cours renvoyés par le serveur mais illisibles, écartés par ``Lenient``.
    /// L'app le signale plutôt que de faire disparaître un créneau en silence.
    public let unreadableCourses: Int

    public init(
        week: ISOWeek,
        selection: ScheduleSelection,
        courses: [ScheduledCourse],
        version: Int? = nil,
        fetchedAt: Date = .now,
        unreadableCourses: Int = 0
    ) {
        self.week = week
        self.selection = selection
        self.courses = courses.sorted { ($0.day, $0.startTime) < ($1.day, $1.startTime) }
        self.version = version
        self.fetchedAt = fetchedAt
        self.unreadableCourses = unreadableCourses
    }

    /// Décodage tolérant, pour la même raison que ``Referential`` : une valeur
    /// par défaut ne rend pas une clé facultative au décodage. Sans cela,
    /// ajouter un champ ici rendrait illisibles toutes les semaines écrites par
    /// la version précédente de l'app — c'est-à-dire le cache hors ligne, la
    /// seule chose qui reste à afficher quand le réseau tombe.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        week = try container.decode(ISOWeek.self, forKey: .week)
        selection = try container.decode(ScheduleSelection.self, forKey: .selection)
        courses = try container.decodeIfPresent(Lenient<ScheduledCourse>.self, forKey: .courses)?.values ?? []
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .distantPast
        unreadableCourses = try container.decodeIfPresent(Int.self, forKey: .unreadableCourses) ?? 0
    }

    /// Aucun cours de la semaine.
    ///
    /// C'est ainsi qu'on reconnaît les vacances : l'API n'expose pas de
    /// calendrier scolaire, et un compteur de cours à zéro est le signal le plus
    /// fiable dont on dispose — il ne coûte d'ailleurs aucune requête
    /// supplémentaire.
    public var isEmpty: Bool { courses.isEmpty }

    public func courses(on day: Weekday) -> [ScheduledCourse] {
        courses.filter { $0.day == day }
    }

    public func courses(on date: Date) -> [ScheduledCourse] {
        guard week.contains(date) else { return [] }
        return courses(on: Weekday(date: date))
    }

    /// Les jours de la semaine qui portent au moins un cours.
    public var busyDays: Set<Weekday> {
        Set(courses.map(\.day))
    }

    /// Le créneau le plus tôt et le plus tard de la semaine, en minutes depuis
    /// minuit. Permet de resserrer la grille sur ce qui est réellement occupé
    /// plutôt que d'afficher une amplitude vide.
    public func timeRange(using durations: [String: Int]) -> ClosedRange<Int>? {
        guard let first = courses.map(\.startTime).min(),
              let last = courses.map({ $0.endTime(using: durations) }).max()
        else { return nil }
        return first...last
    }

    /// Le même contenu peut arriver deux fois — au lancement depuis le cache,
    /// puis depuis le réseau. Comparer les cours seuls, sans les horodatages,
    /// évite de réanimer l'écran pour rien.
    public func hasSameCourses(as other: WeekSchedule) -> Bool {
        courses == other.courses
    }
}

/// Ce qu'a donné une demande d'emploi du temps.
///
/// L'app affiche `cached` immédiatement s'il arrive, puis remplace par `fresh`.
/// `failed` transporte ce qu'on avait déjà, pour qu'une panne réseau se traduise
/// par un bandeau discret et non par un écran vide.
public enum ScheduleLoad: Sendable {
    case cached(WeekSchedule)
    case fresh(WeekSchedule)
    case failed(APIError, stale: WeekSchedule?)

    public var schedule: WeekSchedule? {
        switch self {
        case .cached(let value), .fresh(let value): value
        case .failed(_, let stale): stale
        }
    }

    public var isFresh: Bool {
        if case .fresh = self { return true }
        return false
    }
}

/// Le résultat d'un sondage de version pendant que l'app est ouverte.
public enum UpdateCheck: Sendable, Equatable {
    /// La version du serveur est celle qu'on a déjà.
    case unchanged
    /// L'emploi du temps a bougé, voici la nouvelle version.
    case changed(WeekSchedule)
    /// Impossible de savoir — réseau, ou version inconnue de notre côté.
    case indeterminate

    public var didChange: Bool {
        if case .changed = self { return true }
        return false
    }
}
