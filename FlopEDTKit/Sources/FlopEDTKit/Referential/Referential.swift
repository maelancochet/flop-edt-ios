import Foundation

/// Tout ce que la v1 codait en dur, tel que le serveur l'annonce.
///
/// Découpé en deux parties parce qu'elles ne coûtent pas la même chose :
/// - le **socle** (départements, horaires de journée) tient en deux requêtes de
///   quelques centaines d'octets et sert à tous les écrans ;
/// - les **données par département** (promos, arbre des groupes, types de cours)
///   représentent trois requêtes chacune. Les charger pour les cinq départements
///   prend environ 3 s, alors qu'un étudiant n'en consulte qu'un. Elles sont donc
///   chargées à la demande et conservées ensuite.
public struct Referential: Codable, Hashable, Sendable {
    public var departments: [Department]
    public var timeSettings: [TimeSettings]
    /// Le vocabulaire des niveaux de groupe, tous départements confondus.
    public var groupTypes: [GroupType]
    /// Indexé par abrégé de département.
    public var departmentData: [String: DepartmentReferential]
    public var fetchedAt: Date

    public init(
        departments: [Department] = [],
        timeSettings: [TimeSettings] = [],
        groupTypes: [GroupType] = [],
        departmentData: [String: DepartmentReferential] = [:],
        fetchedAt: Date = .distantPast
    ) {
        self.departments = departments
        self.timeSettings = timeSettings
        self.groupTypes = groupTypes
        self.departmentData = departmentData
        self.fetchedAt = fetchedAt
    }

    /// Décodage tolérant : chaque champ absent retombe sur sa valeur vide.
    ///
    /// Une valeur par défaut ne suffit pas — le décodeur synthétisé par Swift
    /// exige quand même la clé. Sans cette tolérance, ajouter un champ dans une
    /// nouvelle version de l'app rendait illisible le fichier écrit par la
    /// précédente : le cache était silencieusement abandonné et tout le
    /// référentiel retéléchargé, y compris les départements conservés pour
    /// l'usage hors ligne.
    ///
    /// Ce qui manque sera de toute façon rempli au prochain rafraîchissement.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        departments = try container.decodeIfPresent([Department].self, forKey: .departments) ?? []
        timeSettings = try container.decodeIfPresent([TimeSettings].self, forKey: .timeSettings) ?? []
        groupTypes = try container.decodeIfPresent([GroupType].self, forKey: .groupTypes) ?? []
        departmentData = try container.decodeIfPresent(
            [String: DepartmentReferential].self, forKey: .departmentData
        ) ?? [:]
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .distantPast
    }

    public var isEmpty: Bool { departments.isEmpty }

    public func department(abbrev: String) -> Department? {
        departments.first { $0.abbrev == abbrev }
    }

    /// Les horaires de journée du département, avec repli sur 8h–20h du lundi au
    /// vendredi. Un département absent ne doit jamais rendre l'écran inaffichable.
    public func timeSettings(forDepartment abbrev: String) -> TimeSettings {
        guard let id = department(abbrev: abbrev)?.id,
              let settings = timeSettings.first(where: { $0.department == id })
        else { return .fallback }
        return settings
    }

    public func data(forDepartment abbrev: String) -> DepartmentReferential? {
        departmentData[abbrev]
    }

    public func isStale(maxAge: TimeInterval, now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) > maxAge
    }

    // MARK: Types de groupe

    /// Le type d'un groupe — `TD`, `TP`, `CE`… — tel que le département le nomme.
    ///
    /// La jointure se fait sur (promo, nom) : les identifiants de groupe de
    /// l'arbre ne sont pas exposés par `groups/structural/tree/`, mais le couple
    /// est unique — vérifié sur les cinq départements.
    public func groupTypeName(department: String, promo: String, group: String) -> String? {
        guard let data = departmentData[department],
              let programme = data.trainingPrograms.first(where: { $0.abbrev == promo }),
              let entry = data.structuralGroups.first(where: {
                  $0.trainProg == programme.id && $0.name == group
              })
        else { return nil }
        return groupTypes.first { $0.id == entry.type }?.name
    }

    /// Le type commun à plusieurs groupes d'une même promo, s'il y en a un.
    ///
    /// Renvoie `nil` quand ils n'ont pas tous le même type : INFO BUT2 mélange
    /// un `12` de type `CE` et un `3` de type `TD` au même niveau. L'appelant
    /// retombe alors sur un libellé générique.
    public func commonGroupTypeName(
        department: String,
        promo: String,
        groups: [String]
    ) -> String? {
        guard !groups.isEmpty else { return nil }
        let names = groups.map { groupTypeName(department: department, promo: promo, group: $0) }
        guard let first = names.first ?? nil, names.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// Reprend le socle d'un autre référentiel en conservant les départements
    /// déjà chargés — un rafraîchissement du socle ne doit pas les jeter.
    public func merging(base other: Referential) -> Referential {
        Referential(
            departments: other.departments,
            timeSettings: other.timeSettings,
            groupTypes: other.groupTypes,
            departmentData: departmentData,
            fetchedAt: other.fetchedAt
        )
    }

    public func merging(_ data: DepartmentReferential, forDepartment abbrev: String) -> Referential {
        var copy = self
        copy.departmentData[abbrev] = data
        return copy
    }

    /// Le même contenu, mais daté comme n'ayant jamais été confirmé par le
    /// serveur. Sert à l'instantané embarqué, dont on ignore l'âge réel au
    /// moment de l'installation.
    public func markedAsUnverified() -> Referential {
        Referential(
            departments: departments,
            timeSettings: timeSettings,
            groupTypes: groupTypes,
            departmentData: departmentData.mapValues { $0.markedAsUnverified() },
            fetchedAt: .distantPast
        )
    }
}

/// Les données propres à un département.
public struct DepartmentReferential: Codable, Hashable, Sendable {
    public var trainingPrograms: [TrainingProgram]
    public var groupTree: GroupTree
    public var courseTypes: [CourseType]
    /// La même hiérarchie à plat, pour le type de chaque groupe.
    public var structuralGroups: [StructuralGroup]
    public var fetchedAt: Date

    public init(
        trainingPrograms: [TrainingProgram],
        groupTree: GroupTree,
        courseTypes: [CourseType],
        structuralGroups: [StructuralGroup] = [],
        fetchedAt: Date = .distantPast
    ) {
        self.trainingPrograms = trainingPrograms
        self.groupTree = groupTree
        self.courseTypes = courseTypes
        self.structuralGroups = structuralGroups
        self.fetchedAt = fetchedAt
    }

    /// Décodage tolérant, pour la même raison que ``Referential``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trainingPrograms = try container.decodeIfPresent(
            [TrainingProgram].self, forKey: .trainingPrograms
        ) ?? []
        groupTree = try container.decodeIfPresent(GroupTree.self, forKey: .groupTree)
            ?? GroupTree(roots: [])
        courseTypes = try container.decodeIfPresent([CourseType].self, forKey: .courseTypes) ?? []
        structuralGroups = try container.decodeIfPresent(
            [StructuralGroup].self, forKey: .structuralGroups
        ) ?? []
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .distantPast
    }

    /// Les durées indexées par type de cours, prêtes pour
    /// ``ScheduledCourse/duration(using:)``.
    public var durationsByType: [String: Int] {
        Dictionary(courseTypes.map { ($0.name, $0.duration) }, uniquingKeysWith: { first, _ in first })
    }

    /// Les promos réellement sélectionnables : présentes au référentiel **et**
    /// pourvues d'au moins un groupe dans l'arbre. Une promo déclarée sans
    /// groupe ne mènerait qu'à un écran vide.
    public var selectablePrograms: [TrainingProgram] {
        let withGroups = Set(groupTree.promos)
        return trainingPrograms.filter { withGroups.contains($0.abbrev) }
    }

    public func isStale(maxAge: TimeInterval, now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) > maxAge
    }

    public func markedAsUnverified() -> DepartmentReferential {
        DepartmentReferential(
            trainingPrograms: trainingPrograms,
            groupTree: groupTree,
            courseTypes: courseTypes,
            structuralGroups: structuralGroups,
            fetchedAt: .distantPast
        )
    }
}
