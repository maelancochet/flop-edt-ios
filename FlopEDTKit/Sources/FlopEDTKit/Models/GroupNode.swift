import Foundation

/// `GET /groups/structural/tree/?dept=`
///
/// L'arbre des groupes d'un département, tel que le serveur le renvoie. Ce type
/// remplace les cinq structures codées en dur de `GroupHierarchyManager`, qui
/// étaient déjà fausses en v1 : l'arbre d'INFO BUT3 y était vide, et CS2 était
/// resté sur `2FA` / `2FI` alors que le serveur annonce `2G1` / `2G2`.
///
/// La profondeur des feuilles varie selon le département **et** la promo — de 1
/// niveau pour LPMA à 3 pour INFO BUT2. Toute navigation doit donc descendre
/// récursivement jusqu'à une feuille, sans présumer du nombre de niveaux.
///
/// Volontairement **pas** `Identifiable` : un nœud isolé ne peut pas fournir
/// d'identité stable. `promo` n'est renseigné que sur les racines, et `1A`
/// existe à l'identique dans plusieurs promos d'un même département. Pour
/// identifier un groupe, il faut son chemin complet — voir ``GroupPath``.
public struct GroupNode: Codable, Hashable, Sendable {
    public let name: String
    /// Nom du groupe parent. Vaut la chaîne `"null"` sur les racines — l'API
    /// renvoie bien le mot, pas un `null` JSON.
    public let parent: String?
    /// Renseigné sur les racines uniquement : l'abrégé de la promo (`BUT1`).
    public let promo: String?
    public let promotxt: String?
    public let buttxt: String?
    public let row: Int?
    public let children: [GroupNode]?

    public init(
        name: String,
        parent: String? = nil,
        promo: String? = nil,
        promotxt: String? = nil,
        buttxt: String? = nil,
        row: Int? = nil,
        children: [GroupNode]? = nil
    ) {
        self.name = name
        self.parent = parent
        self.promo = promo
        self.promotxt = promotxt
        self.buttxt = buttxt
        self.row = row
        self.children = children
    }

    public var subgroups: [GroupNode] { children ?? [] }

    /// Un groupe sans sous-groupe : le niveau le plus fin sélectionnable.
    public var isLeaf: Bool { subgroups.isEmpty }

    /// Tous les groupes de ce sous-arbre, racine comprise, en profondeur d'abord.
    public var flattened: [GroupNode] {
        [self] + subgroups.flatMap(\.flattened)
    }

    /// Les groupes les plus fins de ce sous-arbre.
    public var leaves: [GroupNode] {
        isLeaf ? [self] : subgroups.flatMap(\.leaves)
    }

    /// Le chemin depuis ce nœud jusqu'au groupe nommé, inclus.
    ///
    /// Sert à ré-ouvrir l'onboarding sur la sélection enregistrée. Le filtrage
    /// des cours, lui, n'en a plus besoin : `lineage=true` le fait côté serveur.
    public func path(to groupName: String) -> [GroupNode]? {
        if name == groupName { return [self] }
        for child in subgroups {
            if let tail = child.path(to: groupName) {
                return [self] + tail
            }
        }
        return nil
    }
}

/// Un groupe situé dans son arbre : la promo, plus le chemin de la racine
/// jusqu'à lui.
///
/// C'est le type à faire circuler dans l'interface. Il porte tout ce qu'il faut
/// pour construire la requête (`train_prog` + `group`) et fournit une identité
/// réellement unique, là où le nom seul ne l'est pas.
public struct GroupPath: Hashable, Sendable, Identifiable {
    /// L'abrégé de la promo, à passer en `train_prog`.
    public let promo: String
    /// De la racine jusqu'au groupe, inclus. Jamais vide.
    public let nodes: [GroupNode]

    public init(promo: String, nodes: [GroupNode]) {
        precondition(!nodes.isEmpty, "un chemin de groupe contient au moins un nœud")
        self.promo = promo
        self.nodes = nodes
    }

    public var group: GroupNode { nodes[nodes.count - 1] }

    /// Le nom à passer en `group` dans la requête.
    public var name: String { group.name }

    public var isLeaf: Bool { group.isLeaf }

    public var id: String { ([promo] + nodes.map(\.name)).joined(separator: "/") }

    /// « CE › 1 › 1A », pour rappeler à l'utilisateur ce qu'il a choisi.
    public var displayPath: String {
        nodes.map(\.name).joined(separator: " › ")
    }

    fileprivate func appending(_ node: GroupNode) -> GroupPath {
        GroupPath(promo: promo, nodes: nodes + [node])
    }
}

/// L'arbre complet d'un département : une racine par promo.
public struct GroupTree: Codable, Hashable, Sendable {
    public let roots: [GroupNode]

    public init(roots: [GroupNode]) {
        self.roots = roots
    }

    /// Les racines d'une promo donnée.
    ///
    /// INFO a trois racines toutes nommées `CE`, distinguées par leur seul champ
    /// `promo` — d'où le filtrage sur la promo et non sur le nom.
    public func roots(ofPromo promo: String) -> [GroupNode] {
        roots.filter { $0.promo == promo }
    }

    public func leaves(ofPromo promo: String) -> [GroupNode] {
        roots(ofPromo: promo).flatMap(\.leaves)
    }

    /// Le chemin vers un groupe à l'intérieur d'une promo, racine comprise.
    public func path(to groupName: String, inPromo promo: String) -> GroupPath? {
        for root in roots(ofPromo: promo) {
            if let nodes = root.path(to: groupName) {
                return GroupPath(promo: promo, nodes: nodes)
            }
        }
        return nil
    }

    /// Tous les groupes les plus fins d'une promo, chacun avec son chemin.
    ///
    /// C'est ce que consomme l'écran de sélection : chaque entrée sait déjà quoi
    /// envoyer au serveur, sans avoir à reparcourir l'arbre.
    public func leafPaths(ofPromo promo: String) -> [GroupPath] {
        roots(ofPromo: promo).flatMap { root in
            descend(from: GroupPath(promo: promo, nodes: [root]))
        }
    }

    /// Toutes les feuilles du département, toutes promos confondues.
    public var allLeafPaths: [GroupPath] {
        promos.flatMap { leafPaths(ofPromo: $0) }
    }

    private func descend(from path: GroupPath) -> [GroupPath] {
        path.isLeaf ? [path] : path.group.subgroups.flatMap { descend(from: path.appending($0)) }
    }

    /// Les promos réellement présentes dans l'arbre.
    ///
    /// Peut différer de `/fetch/idtrainprog/` si une promo est déclarée sans
    /// aucun groupe : dans ce cas elle n'est pas sélectionnable.
    public var promos: [String] {
        var seen = Set<String>()
        return roots.compactMap(\.promo).filter { seen.insert($0).inserted }
    }
}
