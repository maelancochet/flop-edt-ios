import Foundation

/// `GET /groups/types/`
///
/// Le vocabulaire des niveaux de groupe : `CE`, `CM`, `TD`, `TP`… C'est ce que
/// l'écran de sélection affiche en en-tête, à la place du nom interne de la
/// racine — « CE » ne veut rien dire pour un étudiant.
///
/// ⚠️ Le paramètre `?dept=` est ignoré par le serveur : la réponse contient les
/// types de tous les départements, distingués par leur `department`. On récupère
/// donc la liste entière, une fois, avec le socle du référentiel.
public struct GroupType: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    /// Identifiant du département, à croiser avec ``Department/id``.
    public let department: Int?

    public init(id: Int, name: String, department: Int? = nil) {
        self.id = id
        self.name = name
        self.department = department
    }
}

/// `GET /groups/structural/?dept=`
///
/// La version à plat de l'arbre des groupes. Elle porte deux informations que
/// `groups/structural/tree/` n'expose pas : le `type` du groupe, et `basic`.
///
/// On la charge en plus de l'arbre plutôt qu'à sa place : l'arbre donne déjà la
/// hiérarchie dans la forme exacte dont l'interface a besoin, et les deux
/// requêtes partent en parallèle.
public struct StructuralGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let size: Int
    /// Groupe terminal — le niveau le plus fin.
    public let basic: Bool
    /// Identifiant de la promo, à croiser avec ``TrainingProgram/id``.
    public let trainProg: Int
    /// Identifiant du type, à croiser avec ``GroupType/id``.
    public let type: Int
    public let parentGroups: [Int]

    public init(
        id: Int,
        name: String,
        size: Int = 0,
        basic: Bool,
        trainProg: Int,
        type: Int,
        parentGroups: [Int] = []
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.basic = basic
        self.trainProg = trainProg
        self.type = type
        self.parentGroups = parentGroups
    }
}
