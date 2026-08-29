import Foundation

/// `GET /fetch/scheduledcourses/?dept=&week=&year=&train_prog=&group=&lineage=true`
///
/// Un créneau placé à l'emploi du temps.
///
/// Le décodage est **tolérant** sur tout ce qui n'est pas indispensable à
/// l'affichage. La raison tient à un cas observé en production : le serveur
/// renvoie `"number": null` sur certains cours (CS1/1GB2, semaines 36 et 40 de
/// 2026). Avec un `Int` non optionnel, `JSONDecoder` échoue — et comme il décode
/// un tableau, c'est **toute la semaine** qui devient illisible pour un seul
/// cours mal formé. Un champ décoratif absent ne doit jamais coûter l'emploi du
/// temps entier.
public struct ScheduledCourse: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let room: RoomRef
    /// Minutes depuis minuit.
    public let startTime: Int
    public let day: Weekday
    public let course: Course
    public let tutor: String?
    public let idVisio: String?
    /// Numéro d'occurrence du cours. Décoratif, et **nullable côté serveur**.
    public let number: Int?

    public init(
        id: Int,
        room: RoomRef,
        startTime: Int,
        day: Weekday,
        course: Course,
        tutor: String? = nil,
        idVisio: String? = nil,
        number: Int? = nil
    ) {
        self.id = id
        self.room = room
        self.startTime = startTime
        self.day = day
        self.course = course
        self.tutor = tutor
        self.idVisio = idVisio
        self.number = number
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Sans ces quatre-là, le créneau n'est pas plaçable : leur absence est
        // une vraie erreur, et le cours est écarté par ``Lenient``.
        id = try container.decode(Int.self, forKey: .id)
        startTime = try container.decode(Int.self, forKey: .startTime)
        day = try container.decode(Weekday.self, forKey: .day)
        course = try container.decode(Course.self, forKey: .course)

        room = try container.decodeIfPresent(RoomRef.self, forKey: .room) ?? .unknown
        tutor = try container.decodeIfPresent(String.self, forKey: .tutor)
        idVisio = try container.decodeIfPresent(String.self, forKey: .idVisio)
        number = try container.decodeIfPresent(Int.self, forKey: .number)
    }

    /// La durée n'est pas dans la réponse : elle dépend du type de cours, donné
    /// par `/courses/type/?dept=`. Repli à 90 min pour un type inconnu, afin
    /// qu'un nouveau type n'efface pas le créneau de l'affichage.
    public func duration(using types: [String: Int]) -> Int {
        types[course.type] ?? 90
    }

    public func endTime(using types: [String: Int]) -> Int {
        startTime + duration(using: types)
    }
}

public struct RoomRef: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    /// Un cours sans salle reste affichable : mieux vaut un tiret qu'un trou
    /// dans l'emploi du temps.
    static let unknown = RoomRef(id: -1, name: "—")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? -1
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "—"
    }
}

public struct Course: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let type: String
    public let roomType: String
    public let week: Int
    public let year: Int
    public let groups: [CourseGroup]
    public let suppTutor: [SupplementaryTutor]
    public let module: Module
    public let payModule: Module?
    public let isGraded: Bool

    public init(
        id: Int,
        type: String,
        roomType: String = "",
        week: Int = 0,
        year: Int = 0,
        groups: [CourseGroup] = [],
        suppTutor: [SupplementaryTutor] = [],
        module: Module,
        payModule: Module? = nil,
        isGraded: Bool = false
    ) {
        self.id = id
        self.type = type
        self.roomType = roomType
        self.week = week
        self.year = year
        self.groups = groups
        self.suppTutor = suppTutor
        self.module = module
        self.payModule = payModule
        self.isGraded = isGraded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        module = try container.decode(Module.self, forKey: .module)

        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        roomType = try container.decodeIfPresent(String.self, forKey: .roomType) ?? ""
        week = try container.decodeIfPresent(Int.self, forKey: .week) ?? 0
        year = try container.decodeIfPresent(Int.self, forKey: .year) ?? 0
        groups = try container.decodeIfPresent([CourseGroup].self, forKey: .groups) ?? []
        suppTutor = try container.decodeIfPresent([SupplementaryTutor].self, forKey: .suppTutor) ?? []
        payModule = try container.decodeIfPresent(Module.self, forKey: .payModule)
        isGraded = try container.decodeIfPresent(Bool.self, forKey: .isGraded) ?? false
    }
}

public struct CourseGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let trainProg: String
    public let name: String
    public let isStructural: Bool

    public init(id: Int, trainProg: String, name: String, isStructural: Bool = true) {
        self.id = id
        self.trainProg = trainProg
        self.name = name
        self.isStructural = isStructural
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? -1
        trainProg = try container.decodeIfPresent(String.self, forKey: .trainProg) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isStructural = try container.decodeIfPresent(Bool.self, forKey: .isStructural) ?? true
    }
}

public struct Module: Codable, Hashable, Sendable {
    public let name: String
    public let abbrev: String
    public let display: ModuleDisplay

    public init(name: String, abbrev: String, display: ModuleDisplay) {
        self.name = name
        self.abbrev = abbrev
        self.display = display
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        abbrev = try container.decodeIfPresent(String.self, forKey: .abbrev) ?? ""
        display = try container.decodeIfPresent(ModuleDisplay.self, forKey: .display) ?? .neutral
    }
}

public struct ModuleDisplay: Codable, Hashable, Sendable {
    /// Couleur hexadécimale, par exemple `#ffa500`.
    public let colorBg: String
    public let colorTxt: String

    public init(colorBg: String, colorTxt: String) {
        self.colorBg = colorBg
        self.colorTxt = colorTxt
    }

    /// Couleurs de repli : la carte retombe alors sur la teinte de l'app.
    static let neutral = ModuleDisplay(colorBg: "", colorTxt: "")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colorBg = try container.decodeIfPresent(String.self, forKey: .colorBg) ?? ""
        colorTxt = try container.decodeIfPresent(String.self, forKey: .colorTxt) ?? ""
    }
}

/// Les enseignants supplémentaires.
///
/// La forme réelle relevée sur la prod est `{"username": "…"}`. La v1 gérait
/// `String` et `{"name": …}` ; les trois sont acceptées ici, faute de garantie
/// sur celle que le serveur choisira.
public struct SupplementaryTutor: Codable, Hashable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            name = text
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .username)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? ""
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case username
    }
}
