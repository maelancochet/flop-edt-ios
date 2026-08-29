import Foundation

/// Le catalogue des requêtes utilisées par l'application.
///
/// Tout est regroupé ici pour qu'aucun chemin d'URL ne traîne dans les vues, et
/// pour que la surface d'API réellement consommée tienne sur un écran.
public enum FlopEndpoints {
    // MARK: Référentiel — chargé au premier lancement, revalidé en tâche de fond

    public static var departments: Endpoint<[Department]> {
        Endpoint(path: "fetch/alldepts/")
    }

    public static func trainingPrograms(dept: String) -> Endpoint<[TrainingProgram]> {
        Endpoint(path: "fetch/idtrainprog/", query: ["dept": dept])
    }

    public static func groupTree(dept: String) -> Endpoint<[GroupNode]> {
        Endpoint(path: "groups/structural/tree/", query: ["dept": dept])
    }

    /// L'arbre à plat, qui porte le type de chaque groupe.
    public static func structuralGroups(dept: String) -> Endpoint<[StructuralGroup]> {
        Endpoint(path: "groups/structural/", query: ["dept": dept])
    }

    /// Le vocabulaire des niveaux (`CE`, `TD`, `TP`…), tous départements
    /// confondus : le serveur ignore `?dept=`, autant l'assumer et ne le
    /// demander qu'une fois avec le socle.
    public static var groupTypes: Endpoint<[GroupType]> {
        Endpoint(path: "groups/types/")
    }

    public static func courseTypes(dept: String) -> Endpoint<[CourseType]> {
        Endpoint(path: "courses/type/", query: ["dept": dept])
    }

    /// Volontairement sans paramètre : filtrer côté serveur échoue
    /// (`?department=INFO` invalide, `?department=<id>` redirige vers le login).
    /// On récupère tous les départements et on filtre sur `TimeSettings.department`.
    public static var timeSettings: Endpoint<[TimeSettings]> {
        Endpoint(path: "base/timesettings/")
    }

    // MARK: Emploi du temps

    /// L'emploi du temps d'un groupe pour une semaine.
    ///
    /// `lineage: true` fait remonter les groupes parents **côté serveur** : un
    /// étudiant de `1A` reçoit aussi les cours de `1` et de `CE`. C'est ce qui
    /// rend inutiles les 344 lignes de `GroupHierarchyManager` et les trois
    /// filtres `filtreCM` / `filtreGroupe` / `filtreSousGroupe` de la v1.
    ///
    /// `trainProg` est obligatoire dès que `group` est fourni, sinon le serveur
    /// répond « A training programme should be given when a group name is given ».
    ///
    /// La réponse est décodée en ``Lenient`` : un cours mal formé est écarté
    /// plutôt que de rendre la semaine entière illisible.
    public static func schedule(
        dept: String,
        week: ISOWeek,
        trainProg: String,
        group: String,
        lineage: Bool = true
    ) -> Endpoint<Lenient<ScheduledCourse>> {
        Endpoint(
            path: "fetch/scheduledcourses/",
            query: [
                "dept": dept,
                "week": String(week.week),
                "year": String(week.year),
                "train_prog": trainProg,
                "group": group,
                "lineage": lineage ? "true" : "false"
            ]
        )
    }

    /// Tous les cours d'un département sur une semaine — la base du calcul des
    /// salles libres. Nettement plus lourd (67 Ko contre 9,8 Ko) : à ne demander
    /// que pour cet écran.
    public static func departmentSchedule(dept: String, week: ISOWeek) -> Endpoint<Lenient<ScheduledCourse>> {
        Endpoint(
            path: "fetch/scheduledcourses/",
            query: ["dept": dept, "week": String(week.week), "year": String(week.year)]
        )
    }

    public static func weekInfo(dept: String, week: ISOWeek) -> Endpoint<WeekInfo> {
        Endpoint(
            path: "extra/week-infos/",
            query: ["dept": dept, "week": String(week.week), "year": String(week.year)]
        )
    }

    // MARK: Salles

    public static func rooms(dept: String) -> Endpoint<[Room]> {
        Endpoint(path: "rooms/room/", query: ["dept": dept])
    }

    public static func roomUnavailabilities(dept: String, week: ISOWeek) -> Endpoint<Lenient<RoomUnavailability>> {
        Endpoint(
            path: "fetch/unavailableroom/",
            query: ["dept": dept, "week": String(week.week), "year": String(week.year)]
        )
    }
}
