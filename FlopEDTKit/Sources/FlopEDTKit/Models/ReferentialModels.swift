import Foundation

/// `GET /fetch/alldepts/`
///
/// L'API ne renvoie que l'abrégé. Aucun endpoint accessible en lecture n'expose
/// de libellé long : la décoration (nom complet, icône) est du ressort de la
/// couche présentation, avec repli sur `abbrev` pour qu'un département ajouté en
/// cours d'année reste utilisable sans mise à jour de l'app.
public struct Department: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let abbrev: String

    public init(id: Int, abbrev: String) {
        self.id = id
        self.abbrev = abbrev
    }
}

/// `GET /fetch/idtrainprog/?dept=`
///
/// Une promo. Attention : ce n'est pas réductible à une année d'étude — RT
/// expose `BUT2` et `BUT2A` (alternance), qui ont chacune leur emploi du temps.
/// La v1 les confondait en les rangeant sous « 2e année ».
public struct TrainingProgram: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let abbrev: String
    public let name: String

    public init(id: Int, abbrev: String, name: String) {
        self.id = id
        self.abbrev = abbrev
        self.name = name
    }
}

/// `GET /courses/type/?dept=`
///
/// Remplace les cinq fonctions `endTimeForXXX` codées en dur dans la v1.
public struct CourseType: Codable, Hashable, Sendable {
    public let name: String
    /// Durée en minutes.
    public let duration: Int

    public init(name: String, duration: Int) {
        self.name = name
        self.duration = duration
    }
}

/// `GET /base/timesettings/`
///
/// Amplitude horaire et jours ouvrés du département. Remplace `startHour = 8`
/// et `endHour = 20` codés en dur dans la v1 — les départements diffèrent
/// réellement (INFO finit à 18h45, LPMA à 19h00).
///
/// Ne pas filtrer côté serveur : `?department=INFO` échoue en validation et
/// `?department=<id>` redirige vers le login. On récupère tout et on filtre ici.
public struct TimeSettings: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    /// Minutes depuis minuit.
    public let dayStartTime: Int
    public let dayFinishTime: Int
    public let lunchBreakStartTime: Int
    public let lunchBreakFinishTime: Int
    public let days: [Weekday]
    public let defaultPreferenceDuration: Int
    /// Identifiant du département, à croiser avec `Department.id`.
    public let department: Int

    public init(
        id: Int,
        dayStartTime: Int,
        dayFinishTime: Int,
        lunchBreakStartTime: Int,
        lunchBreakFinishTime: Int,
        days: [Weekday],
        defaultPreferenceDuration: Int,
        department: Int
    ) {
        self.id = id
        self.dayStartTime = dayStartTime
        self.dayFinishTime = dayFinishTime
        self.lunchBreakStartTime = lunchBreakStartTime
        self.lunchBreakFinishTime = lunchBreakFinishTime
        self.days = days
        self.defaultPreferenceDuration = defaultPreferenceDuration
        self.department = department
    }

    /// Repli si le département est absent de la réponse : 8h00 – 20h00, du lundi
    /// au vendredi. L'app doit rester affichable même si cet appel échoue.
    public static let fallback = TimeSettings(
        id: -1,
        dayStartTime: 480,
        dayFinishTime: 1200,
        lunchBreakStartTime: 750,
        lunchBreakFinishTime: 810,
        days: [.monday, .tuesday, .wednesday, .thursday, .friday],
        defaultPreferenceDuration: 90,
        department: -1
    )
}

/// `GET /extra/week-infos/?dept=&week=&year=`
///
/// `version` bouge quand l'emploi du temps de la semaine est modifié. Sert au
/// sondage en session — 70 octets contre 9,8 Ko pour l'emploi du temps complet.
/// Jamais utilisé comme autorité de fraîcheur au lancement : il n'est pas prouvé
/// qu'il s'incrémente à chaque déplacement de cours, et l'app doit rester juste
/// même si ce champ ment.
public struct WeekInfo: Codable, Hashable, Sendable {
    public let version: Int
    public let proposedPref: Int
    public let requiredPref: Int
    public let regen: String

    /// `regen == "I"` et `version == 0` marquent une semaine jamais générée.
    /// Indice utile, mais incomplet : certaines semaines de vacances ont un
    /// `version` non nul. Ne pas en faire un détecteur de vacances.
    public var looksUngenerated: Bool {
        version == 0 && regen.hasPrefix("I")
    }
}
