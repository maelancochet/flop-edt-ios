import Foundation

/// L'emploi du temps choisi par l'utilisateur.
///
/// Trois chaînes suffisent, parce que `lineage=true` fait remonter les groupes
/// parents côté serveur. La v1 en stockait cinq — `trainprog`, `filtreCM`,
/// `filtreGroupe`, `filtreSousGroupe`, `yearhome` — qu'il fallait recalculer par
/// un `switch` sur le département à chaque changement de sélection.
public struct ScheduleSelection: Codable, Hashable, Sendable {
    /// Abrégé du département, par exemple `INFO`.
    public let department: String
    /// Abrégé de la promo, passé en `train_prog`.
    public let promo: String
    /// Nom du groupe, passé en `group`.
    public let group: String

    public init(department: String, promo: String, group: String) {
        self.department = department
        self.promo = promo
        self.group = group
    }

    public init(department: String, path: GroupPath) {
        self.init(department: department, promo: path.promo, group: path.name)
    }

    /// Vérifie que la sélection existe toujours dans le référentiel.
    ///
    /// Les groupes changent d'une année sur l'autre : un étudiant qui rouvre
    /// l'app à la rentrée peut se retrouver avec un groupe supprimé. Mieux vaut
    /// le renvoyer vers la sélection que de le laisser devant un emploi du temps
    /// vide sans explication.
    public func isValid(in data: DepartmentReferential) -> Bool {
        data.groupTree.path(to: group, inPromo: promo) != nil
    }

    public func path(in data: DepartmentReferential) -> GroupPath? {
        data.groupTree.path(to: group, inPromo: promo)
    }
}

/// Là où la sélection survit entre deux lancements.
public protocol SelectionStorage: Sendable {
    func load() -> ScheduleSelection?
    func save(_ selection: ScheduleSelection?)
}

/// Le stockage réel, dans les préférences.
///
/// `UserDefaults` et non un fichier : la sélection est lue au tout premier
/// instant du lancement pour décider entre l'écran de choix et l'emploi du
/// temps, et une lecture synchrone évite un aller-retour d'écran visible.
/// `@unchecked Sendable` : `UserDefaults` est documenté comme sûr entre threads
/// mais n'est pas marqué `Sendable`.
public struct UserDefaultsSelectionStorage: SelectionStorage, @unchecked Sendable {
    public static let key = "schedule.selection"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ScheduleSelection? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? FlopJSON.decoder.decode(ScheduleSelection.self, from: data)
    }

    public func save(_ selection: ScheduleSelection?) {
        guard let selection else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        guard let data = try? FlopJSON.encoder.encode(selection) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

public final class InMemorySelectionStorage: SelectionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ScheduleSelection?

    public init(initial: ScheduleSelection? = nil) {
        stored = initial
    }

    public func load() -> ScheduleSelection? {
        lock.withLock { stored }
    }

    public func save(_ selection: ScheduleSelection?) {
        lock.withLock { stored = selection }
    }
}
