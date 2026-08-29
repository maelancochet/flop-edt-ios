import Foundation

/// Un tableau décodé élément par élément : un objet illisible est écarté, les
/// autres arrivent quand même.
///
/// `JSONDecoder` traite un tableau comme un tout — un seul objet mal formé fait
/// échouer les cent autres. Sur l'emploi du temps, c'est la différence entre
/// « il manque un cours » et « la semaine est vide, réessayez ». Le cas s'est
/// produit en production : `"number": null` sur un TP de CS1/1GB2 rendait
/// illisibles les semaines 36 et 40 de 2026 — celles de la rentrée.
///
/// Le nombre d'éléments écartés est conservé dans ``skipped`` : écarter est
/// préférable à échouer, mais l'app doit pouvoir le dire plutôt que de faire
/// disparaître un cours en silence.
public struct Lenient<Element: Decodable & Sendable>: Decodable, Sendable {
    public let values: [Element]
    /// Nombre d'éléments que le serveur a renvoyés et qu'on n'a pas su lire.
    public let skipped: Int

    public init(values: [Element], skipped: Int = 0) {
        self.values = values
        self.skipped = skipped
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        var skipped = 0
        values.reserveCapacity(container.count ?? 0)

        while !container.isAtEnd {
            // On passe par ``Attempt``, dont le décodage réussit toujours : un
            // `decode` qui échoue ne fait pas forcément avancer le conteneur,
            // ce qui boucle indéfiniment. Cette indirection ne dépend donc pas
            // du détail d'implémentation de `JSONDecoder`.
            let attempt = try container.decode(Attempt<Element>.self)
            if let value = attempt.value {
                values.append(value)
            } else {
                skipped += 1
            }
        }

        self.values = values
        self.skipped = skipped
    }

    private struct Attempt<Wrapped: Decodable>: Decodable {
        let value: Wrapped?

        init(from decoder: any Decoder) throws {
            value = try? Wrapped(from: decoder)
        }
    }
}

/// Se manipule comme le tableau qu'il enveloppe.
extension Lenient: RandomAccessCollection {
    public var startIndex: Int { values.startIndex }
    public var endIndex: Int { values.endIndex }
    public subscript(position: Int) -> Element { values[position] }
}

extension Lenient: Equatable where Element: Equatable {}
extension Lenient: Hashable where Element: Hashable {}
