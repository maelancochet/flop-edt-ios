import Foundation

/// Un créneau pendant lequel une salle est prise.
public struct BusyPeriod: Hashable, Sendable {
    /// Minutes depuis minuit.
    public let start: Int
    public let end: Int
    public let reason: Reason

    public enum Reason: Hashable, Sendable {
        /// Un cours à l'emploi du temps.
        case course(module: String, type: String)
        /// Une indisponibilité déclarée : ménage, maintenance, réunion.
        case unavailable
    }

    public init(start: Int, end: Int, reason: Reason) {
        self.start = start
        self.end = end
        self.reason = reason
    }

    /// Le créneau couvre-t-il cet instant ? Borne de fin exclue : une salle
    /// libérée à 10h00 est disponible à 10h00.
    public func contains(_ minute: Int) -> Bool {
        minute >= start && minute < end
    }
}

/// L'état d'une salle à un instant donné.
public enum RoomStatus: Hashable, Sendable {
    /// Libre. `until` est le début de la prochaine occupation, ou `nil` s'il n'y
    /// en a plus d'ici la fin de la journée.
    case free(until: Int?)
    /// Occupée jusqu'à `until`.
    case busy(until: Int, reason: BusyPeriod.Reason)

    public var isFree: Bool {
        if case .free = self { return true }
        return false
    }

    /// Combien de minutes cet état va-t-il encore durer ? `nil` si rien ne le
    /// borne d'ici la fin de la journée.
    public func remaining(from minute: Int) -> Int? {
        switch self {
        case .free(let until): until.map { max(0, $0 - minute) }
        case .busy(let until, _): max(0, until - minute)
        }
    }
}

public struct RoomAvailability: Hashable, Sendable, Identifiable {
    public let room: String
    public let status: RoomStatus

    public var id: String { room }
    public var isFree: Bool { status.isFree }
}

/// Le calcul des salles libres.
///
/// Trois pièges rendent le calcul naïf faux :
///
/// 1. **Les salles se chevauchent.** Réserver `B101-B102` occupe B101 *et* B102 ;
///    `1er Etage + B219` en bloque sept d'un coup ; `Entretien` bloque B010, B115
///    et B005. D'où l'expansion par ``Room/basicRooms`` — sans elle, on
///    proposerait des salles en réalité prises.
/// 2. **La durée d'un cours n'est pas dans sa réponse.** Elle dépend du type et
///    vient de `/courses/type/?dept=` — un barème **par département**.
/// 3. **Les salles sont partagées entre départements.** C'est le piège le plus
///    coûteux, parce qu'il produit exactement la faute qu'un tel écran ne peut
///    pas se permettre : annoncer libre une salle occupée. La table d'INFO
///    déclare 36 salles appartenant aussi à d'autres départements ; mesuré sur
///    la semaine 12 de 2026, jeudi 10h00, quatre des quinze salles qu'un calcul
///    limité à INFO annonçait libres étaient prises par CS ou GIM (B006, B113,
///    C004, C006). Sur la semaine entière : 60 créneaux faux, 8 salles sur 24.
///
/// D'où la notion de ``Source`` : chaque département apporte ses salles, ses
/// cours, ses indisponibilités et son barème de durées. Les salles **proposées**
/// restent celles du département de l'utilisateur ; l'**occupation** se lit sur
/// toutes les sources.
public struct RoomOccupancy: Sendable {
    /// Ce qu'un département apporte au calcul.
    public struct Source: Sendable {
        public let department: String
        /// Sert à l'expansion des salles composites : `B112+B113` peut n'être
        /// déclarée que chez GIM alors qu'elle bloque une salle d'INFO.
        public let rooms: [Room]
        public let courses: [ScheduledCourse]
        public let unavailabilities: [RoomUnavailability]
        /// Le barème de ce département : un « TD » ne dure pas forcément
        /// autant chez CS que chez INFO.
        public let durations: [String: Int]

        public init(
            department: String = "",
            rooms: [Room] = [],
            courses: [ScheduledCourse] = [],
            unavailabilities: [RoomUnavailability] = [],
            durations: [String: Int] = [:]
        ) {
            self.department = department
            self.rooms = rooms
            self.courses = courses
            self.unavailabilities = unavailabilities
            self.durations = durations
        }
    }

    /// Les salles réellement réservables, triées. Seules les salles de base y
    /// figurent : proposer `B101-B102` alors que B101 est pris n'aurait pas de sens.
    public let rooms: [String]

    /// Départements dont l'occupation n'a pas pu être lue. Non vide, la liste
    /// veut dire que le résultat peut être optimiste — et l'app doit le dire.
    public let missingDepartments: [String]

    private let periods: [Weekday: [String: [BusyPeriod]]]

    /// Le calcul complet.
    ///
    /// - Parameters:
    ///   - offered: les salles du département consulté — celles qu'on propose.
    ///   - sources: toutes les sources d'occupation, y compris ce département.
    ///   - missingDepartments: ceux qu'on n'a pas pu interroger.
    public init(
        offering offered: [Room],
        sources: [Source],
        missingDepartments: [String] = []
    ) {
        // Une salle composite se ramène à ses salles de base ; une salle inconnue
        // de la table se représente elle-même, pour ne pas disparaître du calcul.
        // L'union des tables, et non la seule table locale : une composite
        // déclarée ailleurs doit quand même bloquer nos salles de base.
        var expansion: [String: Set<String>] = [:]
        for source in sources {
            for room in source.rooms {
                let parts = room.basicRooms.isEmpty ? [room.name] : room.basicRooms.map(\.name)
                expansion[room.name, default: []].formUnion(parts)
            }
        }

        self.rooms = offered.filter(\.isBasic).map(\.name).sorted()
        self.missingDepartments = missingDepartments

        var built: [Weekday: [String: [BusyPeriod]]] = [:]

        func add(_ period: BusyPeriod, to name: String, on day: Weekday) {
            for basic in expansion[name] ?? [name] {
                built[day, default: [:]][basic, default: []].append(period)
            }
        }

        for source in sources {
            for course in source.courses {
                let period = BusyPeriod(
                    start: course.startTime,
                    end: course.endTime(using: source.durations),
                    reason: .course(module: course.course.module.abbrev, type: course.course.type)
                )
                add(period, to: course.room.name, on: course.day)
            }

            for entry in source.unavailabilities {
                // `value == 0` signifie indisponible. Les autres valeurs expriment
                // une préférence, pas un blocage : les traiter comme occupées
                // masquerait des salles en réalité utilisables.
                guard entry.value == 0 else { continue }
                add(
                    BusyPeriod(start: entry.startTime, end: entry.endTime, reason: .unavailable),
                    to: entry.room,
                    on: entry.day
                )
            }
        }

        self.periods = built.mapValues { rooms in
            rooms.mapValues { $0.sorted { ($0.start, $0.end) < ($1.start, $1.end) } }
        }
    }

    /// Raccourci mono-département, pour les tests et les aperçus.
    ///
    /// À ne pas utiliser dans l'app : il ignore les cours des autres
    /// départements et annonce donc libres des salles prises.
    public init(
        rooms roomTable: [Room],
        courses: [ScheduledCourse],
        unavailabilities: [RoomUnavailability] = [],
        durations: [String: Int]
    ) {
        self.init(
            offering: roomTable,
            sources: [
                Source(
                    rooms: roomTable,
                    courses: courses,
                    unavailabilities: unavailabilities,
                    durations: durations
                )
            ]
        )
    }

    /// Les créneaux occupés d'une salle, triés.
    public func busyPeriods(for room: String, on day: Weekday) -> [BusyPeriod] {
        periods[day]?[room] ?? []
    }

    public func status(of room: String, on day: Weekday, at minute: Int) -> RoomStatus {
        let dayPeriods = busyPeriods(for: room, on: day)

        guard let index = dayPeriods.firstIndex(where: { $0.contains(minute) }) else {
            let next = dayPeriods.first { $0.start > minute }?.start
            return .free(until: next)
        }

        // Des créneaux qui s'enchaînent sans trou comptent pour une seule
        // occupation : la salle n'est pas rendue entre deux cours consécutifs.
        var end = dayPeriods[index].end
        for period in dayPeriods[(index + 1)...] where period.start <= end {
            end = max(end, period.end)
        }
        return .busy(until: end, reason: dayPeriods[index].reason)
    }

    /// L'état de toutes les salles à un instant donné, par ordre alphabétique.
    public func availability(on day: Weekday, at minute: Int) -> [RoomAvailability] {
        rooms.map { RoomAvailability(room: $0, status: status(of: $0, on: day, at: minute)) }
    }

    /// Les salles libres, les plus longtemps disponibles d'abord.
    ///
    /// Trier ainsi répond à la vraie question de l'utilisateur — « où puis-je
    /// m'installer sans être délogé dans dix minutes ? ». Les salles libres pour
    /// le reste de la journée viennent en tête.
    public func freeRooms(on day: Weekday, at minute: Int) -> [RoomAvailability] {
        availability(on: day, at: minute)
            .filter(\.isFree)
            .sorted { left, right in
                switch (left.status.remaining(from: minute), right.status.remaining(from: minute)) {
                case (nil, nil): left.room < right.room
                case (nil, _): true
                case (_, nil): false
                case (let a?, let b?): a == b ? left.room < right.room : a > b
                }
            }
    }

    public func busyRooms(on day: Weekday, at minute: Int) -> [RoomAvailability] {
        availability(on: day, at: minute).filter { !$0.isFree }
    }

    // MARK: Confort

    /// L'état des salles à une date précise, heure de Blagnac.
    public func availability(at date: Date) -> [RoomAvailability] {
        availability(on: Weekday(date: date), at: FlopCalendar.minutesSinceMidnight(of: date))
    }

    public func freeRooms(at date: Date) -> [RoomAvailability] {
        freeRooms(on: Weekday(date: date), at: FlopCalendar.minutesSinceMidnight(of: date))
    }
}
