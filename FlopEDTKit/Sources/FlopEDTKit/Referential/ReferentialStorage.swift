import Foundation

/// Où le référentiel est conservé entre deux lancements.
///
/// Abstrait pour que les tests n'aient pas à toucher le disque, et pour pouvoir
/// changer de support plus tard sans reprendre le chargeur.
public protocol ReferentialStorage: Sendable {
    func read() throws -> Referential?
    func write(_ referential: Referential) throws
    func clear() throws
}

/// Le stockage réel : un fichier JSON dans Application Support.
///
/// Application Support et non Caches : le système peut vider Caches sous
/// pression disque, ce qui obligerait à repasser par le réseau pour afficher le
/// moindre écran. Le référentiel ne change qu'une fois par an, autant le garder.
public struct FileReferentialStorage: ReferentialStorage {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directory: URL? = nil, fileName: String = "referential.json") throws {
        let base: URL
        if let directory {
            base = directory
        } else {
            base = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("FlopEDT", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent(fileName)
    }

    public func read() throws -> Referential? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try FlopJSON.decoder.decode(Referential.self, from: data)
    }

    public func write(_ referential: Referential) throws {
        let data = try FlopJSON.encoder.encode(referential)
        // Écriture atomique : une interruption ne doit pas laisser un fichier
        // tronqué, qui empêcherait le prochain lancement de démarrer hors ligne.
        try data.write(to: fileURL, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

/// Stockage en mémoire, pour les tests et les aperçus SwiftUI.
public final class InMemoryReferentialStorage: ReferentialStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Referential?
    /// Nombre d'écritures effectuées — permet de vérifier qu'on ne réécrit pas
    /// inutilement à chaque lancement.
    public private(set) var writeCount = 0

    public init(initial: Referential? = nil) {
        stored = initial
    }

    public func read() throws -> Referential? {
        lock.withLock { stored }
    }

    public func write(_ referential: Referential) throws {
        lock.withLock {
            stored = referential
            writeCount += 1
        }
    }

    public func clear() throws {
        lock.withLock {
            stored = nil
        }
    }
}

/// L'instantané livré dans l'application.
///
/// Sans lui, une première installation faite alors que le serveur de l'IUT est
/// indisponible — panne, coupure réseau, wifi captif de la fac — laisserait
/// l'utilisateur devant un écran vide, sans même pouvoir choisir son
/// département. Il est écrasé dès la première réponse du serveur.
public enum BundledReferential {
    public static let resourceName = "referential-snapshot"

    /// `Bundle.module` n'est pas référençable depuis une valeur par défaut
    /// publique — il est interne au package. On le résout donc à l'intérieur.
    public static func load(from bundle: Bundle? = nil) -> Referential? {
        let bundle = bundle ?? .module
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let referential = try? FlopJSON.decoder.decode(Referential.self, from: data)
        else { return nil }
        return referential
    }
}
