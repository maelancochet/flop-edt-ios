import Foundation

/// L'identité d'une semaine en cache.
///
/// La sélection fait partie de la clé : changer de groupe ne doit jamais
/// réafficher l'emploi du temps du groupe précédent.
public struct ScheduleCacheKey: Hashable, Sendable {
    public let selection: ScheduleSelection
    public let week: ISOWeek

    public init(selection: ScheduleSelection, week: ISOWeek) {
        self.selection = selection
        self.week = week
    }

    /// Un nom de fichier sûr, quel que soit le nom du groupe.
    public var fileName: String {
        func sanitised(_ value: String) -> String {
            String(value.map { character in
                character.isLetter || character.isNumber ? character : "-"
            })
        }
        return [
            sanitised(selection.department),
            sanitised(selection.promo),
            sanitised(selection.group),
            "\(week.year)-W\(week.week)"
        ].joined(separator: "_") + ".json"
    }
}

public protocol ScheduleCache: Sendable {
    func read(_ key: ScheduleCacheKey) -> WeekSchedule?
    func write(_ schedule: WeekSchedule, for key: ScheduleCacheKey)
    func removeAll()
}

/// Le cache disque : un fichier par semaine.
///
/// Un fichier par semaine et non un seul gros fichier : chaque téléchargement
/// n'en réécrit qu'un, et l'élagage se fait par simple suppression. Une semaine
/// filtrée pèse environ 10 Ko.
public struct FileScheduleCache: ScheduleCache {
    /// Au-delà, les fichiers les plus anciens sont supprimés. Vingt-quatre
    /// semaines couvrent largement les allers-retours d'un utilisateur autour de
    /// la semaine courante, pour environ 240 Ko.
    public static let maxEntries = 24

    private let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public init() throws {
        let base = try FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FlopEDT/Schedules", isDirectory: true)
        try self.init(directory: base)
    }

    public func read(_ key: ScheduleCacheKey) -> WeekSchedule? {
        let url = directory.appendingPathComponent(key.fileName)
        guard let data = try? Data(contentsOf: url),
              let schedule = try? FlopJSON.decoder.decode(WeekSchedule.self, from: data)
        else { return nil }
        // Un fichier écrit pour une autre sélection n'a rien à faire ici : on
        // s'en assure plutôt que de faire confiance au nom du fichier.
        guard schedule.selection == key.selection, schedule.week == key.week else { return nil }
        return schedule
    }

    public func write(_ schedule: WeekSchedule, for key: ScheduleCacheKey) {
        guard let data = try? FlopJSON.encoder.encode(schedule) else { return }
        try? data.write(to: directory.appendingPathComponent(key.fileName), options: .atomic)
        prune()
    }

    public func removeAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > Self.maxEntries else { return }

        let byDate = files.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
        for file in byDate.dropFirst(Self.maxEntries) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

public final class InMemoryScheduleCache: ScheduleCache, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ScheduleCacheKey: WeekSchedule] = [:]
    public private(set) var writeCount = 0

    public init() {}

    public func read(_ key: ScheduleCacheKey) -> WeekSchedule? {
        lock.withLock { entries[key] }
    }

    public func write(_ schedule: WeekSchedule, for key: ScheduleCacheKey) {
        lock.withLock {
            entries[key] = schedule
            writeCount += 1
        }
    }

    public func removeAll() {
        lock.withLock { entries.removeAll() }
    }
}
