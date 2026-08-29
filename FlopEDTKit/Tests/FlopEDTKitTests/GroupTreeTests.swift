import Foundation
import Testing
@testable import FlopEDTKit

@Suite("Arbre des groupes")
struct GroupTreeTests {

    private func tree(_ fixture: String) throws -> GroupTree {
        GroupTree(roots: try TestSupport.decode([GroupNode].self, from: fixture))
    }

    /// La profondeur des feuilles change d'une promo à l'autre. C'est ce qui
    /// rendait le `switch dept.code` de la v1 ingérable, et ce que la descente
    /// récursive règle une fois pour toutes.
    @Test("La profondeur des feuilles varie selon le département et la promo")
    func varyingDepth() throws {
        let info = try tree("grouptree-INFO")
        let lpma = try tree("grouptree-LPMA")
        let cs = try tree("grouptree-CS")

        func names(_ path: GroupPath?) -> [String]? { path?.nodes.map(\.name) }

        // LPMA : les feuilles sont juste sous la racine.
        #expect(names(lpma.path(to: "TP1", inPromo: "LPMA")) == ["LPMA", "TP1"])

        // INFO BUT1 : deux niveaux.
        #expect(names(info.path(to: "1A", inPromo: "BUT1")) == ["CE", "1", "1A"])

        // INFO BUT2 : trois niveaux, avec le regroupement « 12 ».
        #expect(names(info.path(to: "1A", inPromo: "BUT2")) == ["CE", "12", "1", "1A"])

        // CS3 : profondeurs différentes au sein d'une même promo.
        #expect(names(cs.path(to: "3FA1", inPromo: "CS3")) == ["CS3", "3FA", "3FA1"])
        #expect(names(cs.path(to: "3FI", inPromo: "CS3")) == ["CS3", "3FI"])
    }

    /// Les trois racines d'INFO s'appellent toutes `CE` : seul le champ `promo`
    /// les distingue.
    @Test("Les racines homonymes se distinguent par la promo")
    func rootsShareNames() throws {
        let info = try tree("grouptree-INFO")
        #expect(info.promos == ["BUT1", "BUT2", "BUT3"])
        #expect(Set(info.roots.map(\.name)) == ["CE"])
        #expect(info.roots(ofPromo: "BUT2").count == 1)
    }

    /// L'arbre codé en dur dans la v1 donnait `children: []` pour INFO BUT3 : les
    /// étudiants de troisième année n'avaient pas d'emploi du temps.
    @Test("INFO BUT3 a bien des groupes, contrairement au code figé de la v1")
    func but3IsNotEmpty() throws {
        let info = try tree("grouptree-INFO")
        let leaves = info.leaves(ofPromo: "BUT3").map(\.name)
        #expect(!leaves.isEmpty)
        #expect(Set(leaves) == ["1A", "1B", "2A", "3A", "3B"])
    }

    /// Le référentiel figé de la v1 annonçait `2FA` et `2FI` pour CS2 ; le
    /// serveur renvoie `2G1` et `2G2`.
    @Test("CS2 a changé de groupes depuis la v1")
    func cs2Changed() throws {
        let cs = try tree("grouptree-CS")
        let leaves = Set(cs.leaves(ofPromo: "CS2").map(\.name))
        #expect(leaves == ["2G1", "2G2"])
        #expect(!leaves.contains("2FA"))
    }

    @Test("Une feuille n'a pas de sous-groupe")
    func leavesAreTerminal() throws {
        let info = try tree("grouptree-INFO")
        let leaves = info.roots.flatMap(\.leaves)
        #expect(leaves.allSatisfy { $0.isLeaf })
        #expect(leaves.allSatisfy { $0.subgroups.isEmpty })
    }

    @Test("Un groupe inconnu ne renvoie pas de chemin")
    func unknownGroup() throws {
        let info = try tree("grouptree-INFO")
        #expect(info.path(to: "ZZ", inPromo: "BUT1") == nil)
        // `1A` existe, mais pas dans une promo qui n'existe pas.
        #expect(info.path(to: "1A", inPromo: "BUT9") == nil)
    }

    /// Le même nom de groupe vit dans plusieurs promos : `1A` existe en BUT1, en
    /// BUT2 et en BUT3. L'identité doit les distinguer, sinon les listes SwiftUI
    /// mélangent les lignes et la sélection saute.
    @Test("Des groupes homonymes de promos différentes ont des identités distinctes")
    func identityIsScoped() throws {
        let info = try tree("grouptree-INFO")
        let but1 = try #require(info.leafPaths(ofPromo: "BUT1").first { $0.name == "1A" })
        let but2 = try #require(info.leafPaths(ofPromo: "BUT2").first { $0.name == "1A" })

        #expect(but1.name == but2.name)
        #expect(but1.id != but2.id)
        #expect(but1.id == "BUT1/CE/1/1A")
        #expect(but2.id == "BUT2/CE/12/1/1A")

        let all = info.allLeafPaths
        #expect(Set(all.map(\.id)).count == all.count)
    }

    /// Chaque feuille porte déjà de quoi construire la requête : `train_prog`
    /// vient de `promo`, `group` de `name`.
    @Test("Une feuille sait à quelle promo elle appartient")
    func leafCarriesItsPromo() throws {
        let info = try tree("grouptree-INFO")
        let paths = info.allLeafPaths
        #expect(paths.count == 18)
        #expect(paths.allSatisfy { !$0.promo.isEmpty })
        #expect(paths.allSatisfy { $0.isLeaf })

        let target = try #require(paths.first { $0.promo == "BUT2" && $0.name == "1A" })
        #expect(target.displayPath == "CE › 12 › 1 › 1A")

        let endpoint = FlopEndpoints.schedule(
            dept: "INFO",
            week: ISOWeek(week: 12, year: 2026),
            trainProg: target.promo,
            group: target.name
        )
        let url = try #require(endpoint.url(relativeTo: FlopAPIClient.blagnac)?.absoluteString)
        #expect(url.contains("train_prog=BUT2"))
        #expect(url.contains("group=1A"))
    }

    /// Le chemin retrouvé et le chemin énuméré doivent désigner le même groupe,
    /// sinon rouvrir l'app sur une sélection enregistrée choisirait mal.
    @Test("Retrouver un groupe et l'énumérer donnent le même chemin")
    func lookupMatchesEnumeration() throws {
        for fixture in ["grouptree-INFO", "grouptree-CS", "grouptree-LPMA"] {
            let subject = try tree(fixture)
            for path in subject.allLeafPaths {
                let found = subject.path(to: path.name, inPromo: path.promo)
                #expect(found?.id == path.id, "\(fixture) : \(path.id)")
            }
        }
    }
}
