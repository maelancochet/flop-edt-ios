import Foundation
import Testing
@testable import FlopEDTKit

@Suite("Référentiel")
struct ReferentialTests {

    /// L'instantané est la seule chose qui rende une première installation
    /// possible hors ligne. S'il ne se décode plus, l'app démarre sur un écran
    /// vide sans que rien ne le signale — d'où ce test.
    @Test("L'instantané embarqué est complet et décodable")
    func bundledSnapshotIsUsable() throws {
        let snapshot = try #require(BundledReferential.load())

        #expect(snapshot.departments.map(\.abbrev).sorted() == ["CS", "GIM", "INFO", "LPMA", "RT"])

        for department in snapshot.departments {
            let data = try #require(
                snapshot.data(forDepartment: department.abbrev),
                "\(department.abbrev) absent de l'instantané"
            )
            #expect(!data.trainingPrograms.isEmpty)
            #expect(!data.courseTypes.isEmpty)
            #expect(!data.groupTree.allLeafPaths.isEmpty)

            // Les horaires doivent exister, sinon la grille retombe sur le repli.
            let settings = snapshot.timeSettings(forDepartment: department.abbrev)
            #expect(settings.id != TimeSettings.fallback.id, "\(department.abbrev) sans horaires")

            // Toute promo de l'arbre doit exister au référentiel, sinon la
            // requête partirait avec un `train_prog` inconnu.
            let known = Set(data.trainingPrograms.map(\.abbrev))
            for promo in data.groupTree.promos {
                #expect(known.contains(promo), "\(department.abbrev) : promo \(promo) inconnue")
            }
        }
    }

    /// « CE » ne veut rien dire pour un étudiant. Le nom du niveau vient donc de
    /// l'API, jointure faite sur (promo, nom).
    @Test("Le type de chaque groupe se résout depuis l'instantané")
    func resolvesGroupTypes() throws {
        let snapshot = try #require(BundledReferential.load())

        // INFO BUT1 : les groupes de TD, puis leurs TP.
        #expect(snapshot.groupTypeName(department: "INFO", promo: "BUT1", group: "1") == "TD")
        #expect(snapshot.groupTypeName(department: "INFO", promo: "BUT1", group: "1A") == "TP")
        // LPMA n'a qu'un niveau, et ce sont des TP.
        #expect(snapshot.groupTypeName(department: "LPMA", promo: "LPMA", group: "TP1") == "TP")
        // Un groupe inconnu ne fabrique pas de libellé.
        #expect(snapshot.groupTypeName(department: "INFO", promo: "BUT1", group: "ZZ") == nil)
    }

    @Test("Un niveau homogène a un type commun, un niveau mélangé n'en a pas")
    func resolvesCommonGroupType() throws {
        let snapshot = try #require(BundledReferential.load())

        #expect(snapshot.commonGroupTypeName(
            department: "INFO", promo: "BUT1", groups: ["1", "2", "3", "4"]) == "TD")
        #expect(snapshot.commonGroupTypeName(
            department: "INFO", promo: "BUT1", groups: ["1A", "1B"]) == "TP")

        // INFO BUT2 mélange un « 12 » de type CE et un « 3 » de type TD : aucun
        // libellé ne conviendrait aux deux.
        #expect(snapshot.groupTypeName(department: "INFO", promo: "BUT2", group: "12") == "CE")
        #expect(snapshot.groupTypeName(department: "INFO", promo: "BUT2", group: "3") == "TD")
        #expect(snapshot.commonGroupTypeName(
            department: "INFO", promo: "BUT2", groups: ["12", "3"]) == nil)

        #expect(snapshot.commonGroupTypeName(
            department: "INFO", promo: "BUT1", groups: []) == nil)
    }

    /// Toute feuille doit savoir se nommer, sinon l'écran de sélection retombe
    /// sur un libellé générique là où l'API avait la réponse.
    @Test("Chaque groupe de l'instantané a un type résoluble")
    func everyGroupHasAType() throws {
        let snapshot = try #require(BundledReferential.load())
        for department in snapshot.departments {
            let data = try #require(snapshot.data(forDepartment: department.abbrev))
            for path in data.groupTree.allLeafPaths {
                for node in path.nodes {
                    let name = snapshot.groupTypeName(
                        department: department.abbrev, promo: path.promo, group: node.name)
                    #expect(name != nil, "\(department.abbrev)/\(path.promo)/\(node.name)")
                }
            }
        }
    }

    @Test("L'instantané contient les corrections que la v1 n'avait pas")
    func snapshotIsUpToDate() throws {
        let snapshot = try #require(BundledReferential.load())
        let info = try #require(snapshot.data(forDepartment: "INFO"))
        let cs = try #require(snapshot.data(forDepartment: "CS"))

        // La v1 codait un arbre vide pour INFO BUT3.
        #expect(!info.groupTree.leafPaths(ofPromo: "BUT3").isEmpty)
        // La v1 annonçait 2FA / 2FI pour CS2.
        #expect(Set(cs.groupTree.leafPaths(ofPromo: "CS2").map(\.name)) == ["2G1", "2G2"])
    }

    /// Le scénario réel : l'utilisateur installe une version de l'app qui ajoute
    /// un champ au référentiel. Le fichier écrit par la version précédente doit
    /// rester lisible, sans quoi son cache — et ses données hors ligne — partent
    /// à la poubelle en silence.
    @Test("Un cache écrit par une version antérieure reste lisible")
    func toleratesOlderCacheFormat() throws {
        // Un fichier tel que l'aurait écrit une version ignorant `group_types`
        // et `structural_groups`.
        let legacy = Data("""
        {
          "departments": [{"id": 103, "abbrev": "INFO"}],
          "time_settings": [],
          "department_data": {
            "INFO": {
              "training_programs": [{"id": 189, "abbrev": "BUT1", "name": "Première année"}],
              "group_tree": {"roots": []},
              "course_types": [{"name": "CM", "duration": 85}],
              "fetched_at": "2026-08-01T10:00:00Z"
            }
          },
          "fetched_at": "2026-08-01T10:00:00Z"
        }
        """.utf8)

        let referential = try FlopJSON.decoder.decode(Referential.self, from: legacy)
        #expect(referential.departments.map(\.abbrev) == ["INFO"])
        #expect(referential.groupTypes.isEmpty)
        #expect(referential.data(forDepartment: "INFO")?.structuralGroups.isEmpty == true)
        #expect(referential.data(forDepartment: "INFO")?.courseTypes.count == 1)
        // La date est conservée : le compteur des réglages ne repart pas à zéro.
        #expect(referential.fetchedAt != .distantPast)
    }

    @Test("Un aller-retour par le disque conserve tout")
    func roundTripsThroughStorage() throws {
        let original = try #require(BundledReferential.load())
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storage = try FileReferentialStorage(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try storage.read() == nil)
        try storage.write(original)
        #expect(try storage.read() == original)

        try storage.clear()
        #expect(try storage.read() == nil)
    }

    @Test("Un département inconnu retombe sur des horaires par défaut")
    func timeSettingsFallback() {
        let referential = Referential(departments: [Department(id: 103, abbrev: "INFO")])
        let settings = referential.timeSettings(forDepartment: "INCONNU")
        #expect(settings.dayStartTime == 480)
        #expect(settings.dayFinishTime == 1200)
        #expect(settings.days == [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    @Test("Les durées sont indexées par type de cours")
    func durationsByType() throws {
        let snapshot = try #require(BundledReferential.load())
        let info = try #require(snapshot.data(forDepartment: "INFO"))
        #expect(info.durationsByType["CM"] == 85)
        #expect(info.durationsByType["QCM"] == 20)
    }

    /// Une promo déclarée sans aucun groupe ne mènerait qu'à un écran vide :
    /// elle ne doit pas être proposée.
    @Test("Seules les promos pourvues de groupes sont sélectionnables")
    func selectableProgramsExcludeEmptyOnes() {
        let data = DepartmentReferential(
            trainingPrograms: [
                TrainingProgram(id: 1, abbrev: "BUT1", name: "Première année"),
                TrainingProgram(id: 2, abbrev: "FANTOME", name: "Sans groupe")
            ],
            groupTree: GroupTree(roots: [
                GroupNode(name: "CE", promo: "BUT1", children: [GroupNode(name: "1A", parent: "CE")])
            ]),
            courseTypes: []
        )
        #expect(data.selectablePrograms.map(\.abbrev) == ["BUT1"])
    }

    @Test("La péremption se mesure sur la date de récupération")
    func staleness() {
        let day: TimeInterval = 24 * 3600
        let now = Date()
        let referential = Referential(fetchedAt: now.addingTimeInterval(-2 * day))
        #expect(referential.isStale(maxAge: day, now: now))
        #expect(!referential.isStale(maxAge: 3 * day, now: now))
        #expect(Referential().isStale(maxAge: day, now: now))
    }
}

@Suite("Sélection de l'emploi du temps")
struct ScheduleSelectionTests {

    @Test("La sélection survit à un aller-retour")
    func roundTrips() {
        let storage = InMemorySelectionStorage()
        #expect(storage.load() == nil)

        let selection = ScheduleSelection(department: "INFO", promo: "BUT2", group: "1A")
        storage.save(selection)
        #expect(storage.load() == selection)

        storage.save(nil)
        #expect(storage.load() == nil)
    }

    @Test("Une sélection se construit depuis un chemin de groupe")
    func fromPath() throws {
        let snapshot = try #require(BundledReferential.load())
        let info = try #require(snapshot.data(forDepartment: "INFO"))
        let path = try #require(info.groupTree.path(to: "1A", inPromo: "BUT2"))

        let selection = ScheduleSelection(department: "INFO", path: path)
        #expect(selection.promo == "BUT2")
        #expect(selection.group == "1A")
        #expect(selection.isValid(in: info))
    }

    /// Les groupes changent d'une année sur l'autre. Un étudiant qui rouvre
    /// l'app à la rentrée avec un groupe supprimé doit être renvoyé vers la
    /// sélection, pas laissé devant un emploi du temps vide.
    @Test("Une sélection devenue caduque est détectée")
    func detectsObsoleteSelection() throws {
        let snapshot = try #require(BundledReferential.load())
        let cs = try #require(snapshot.data(forDepartment: "CS"))

        // `2FA` existait en v1, le serveur ne le connaît plus.
        let obsolete = ScheduleSelection(department: "CS", promo: "CS2", group: "2FA")
        #expect(!obsolete.isValid(in: cs))
        #expect(obsolete.path(in: cs) == nil)

        let current = ScheduleSelection(department: "CS", promo: "CS2", group: "2G1")
        #expect(current.isValid(in: cs))
    }

    @Test("Un groupe valide dans une promo ne l'est pas dans une autre")
    func promoScoped() throws {
        let snapshot = try #require(BundledReferential.load())
        let info = try #require(snapshot.data(forDepartment: "INFO"))

        #expect(ScheduleSelection(department: "INFO", promo: "BUT1", group: "4A").isValid(in: info))
        // `4A` n'existe qu'en BUT1.
        #expect(!ScheduleSelection(department: "INFO", promo: "BUT2", group: "4A").isValid(in: info))
    }
}
