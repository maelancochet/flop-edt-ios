import Foundation
import Observation
import FlopEDTKit

/// L'état partagé par tous les écrans.
///
/// Un seul modèle observable plutôt qu'un ViewModel par vue : tout l'état vient
/// du réseau et sert à plusieurs écrans à la fois. Une couche de ViewModels ne
/// ferait que réexposer ce que les stores de `FlopEDTKit` fournissent déjà.
@Observable
final class AppModel {

    /// Ce que l'app doit afficher au lancement.
    enum Phase: Equatable {
        /// Rien à montrer encore — ni cache, ni instantané embarqué.
        case starting
        /// Premier lancement, ou sélection devenue caduque.
        case onboarding
        case schedule(ScheduleSelection)
    }

    private(set) var phase: Phase = .starting
    private(set) var referential = Referential()
    /// Dernière erreur réseau, affichée discrètement sans bloquer l'écran.
    private(set) var lastError: APIError?

    private let client = FlopAPIClient()
    private let loader: ReferentialLoader
    private let selectionStorage: any SelectionStorage
    private(set) var schedule: ScheduleStore?
    let rooms: RoomStore

    init(
        storage: (any ReferentialStorage)? = nil,
        selectionStorage: any SelectionStorage = UserDefaultsSelectionStorage()
    ) {
        let client = FlopAPIClient()
        let resolved = storage ?? ((try? FileReferentialStorage()) ?? InMemoryReferentialStorage())
        self.loader = ReferentialLoader(client: client, storage: resolved)
        self.selectionStorage = selectionStorage
        self.rooms = RoomStore(client: client)
    }

    // MARK: Lancement

    /// Décide de l'écran d'ouverture, puis revalide en tâche de fond.
    ///
    /// Le référentiel local est immédiat : le premier écran s'affiche sans
    /// attendre le réseau, y compris à la toute première installation grâce à
    /// l'instantané livré dans l'app.
    func start() async {
        referential = await loader.loadLocal()

        if let saved = selectionStorage.load() {
            // On repart sur l'emploi du temps enregistré sans attendre : la
            // validité de la sélection sera vérifiée quand les données du
            // département auront été rafraîchies.
            activate(saved)
        } else if !referential.isEmpty {
            phase = .onboarding
        }

        await refreshReferential()

        if phase == .starting {
            // Ni cache, ni instantané, ni réseau : il n'y a plus qu'à réessayer.
            phase = referential.isEmpty ? .starting : .onboarding
        }

        if let saved = selectionStorage.load() {
            await validate(saved)
        }
    }

    /// Revalide le socle, et le seul département suivi.
    ///
    /// Le périmètre compte : l'instantané embarqué livre les cinq départements,
    /// et revalider « tout ce qui est déjà chargé » faisait partir 23 requêtes
    /// à chaque lancement passé 24 h, pour un étudiant qui n'en consulte qu'un.
    private func refreshReferential() async {
        await apply(await loader.refreshIfNeeded(departments: followedDepartments))
    }

    private func apply(_ outcome: RefreshOutcome) async {
        switch outcome {
        case .updated:
            referential = await loader.referential
            lastError = nil
        case .upToDate:
            lastError = nil
        case .failed(let error):
            lastError = error
        }
    }

    /// Le département suivi, s'il y en a un. Sert de périmètre au
    /// rafraîchissement du référentiel.
    private var followedDepartments: [String] {
        guard let saved = selectionStorage.load() else { return [] }
        return [saved.department]
    }

    /// Vérifie qu'un groupe enregistré existe toujours.
    ///
    /// Les groupes changent à chaque rentrée : plutôt que de laisser
    /// l'utilisateur devant un emploi du temps vide sans explication, on le
    /// renvoie vers la sélection.
    private func validate(_ selection: ScheduleSelection) async {
        guard let data = try? await departmentData(selection.department) else { return }
        if !selection.isValid(in: data) {
            selectionStorage.save(nil)
            schedule = nil
            phase = .onboarding
        }
    }

    // MARK: Référentiel

    func departmentData(_ abbrev: String) async throws -> DepartmentReferential {
        let data = try await loader.department(abbrev)
        referential = await loader.referential
        return data
    }

    /// Les données déjà chargées, pour afficher sans attendre.
    func cachedDepartmentData(_ abbrev: String) -> DepartmentReferential? {
        referential.data(forDepartment: abbrev)
    }

    var departments: [Department] { referential.departments }

    /// L'emploi du temps actuellement suivi, s'il y en a un.
    ///
    /// Sert à marquer la ligne active dans l'écran de sélection : sans ça,
    /// l'utilisateur ne sait pas ce qu'il suit déjà.
    var currentSelection: ScheduleSelection? {
        if case .schedule(let selection) = phase { return selection }
        return nil
    }

    /// L'amplitude horaire du département, avec repli sur 8h–20h.
    func timeSettings(for abbrev: String) -> TimeSettings {
        referential.timeSettings(forDepartment: abbrev)
    }

    /// Force la revalidation du référentiel, depuis les réglages.
    ///
    /// Passe par `forceRefresh` et non par `refreshIfNeeded` : le référentiel
    /// venant d'être revalidé au lancement, le garde de fraîcheur de 24 h
    /// court-circuitait et le bouton ne lançait aucune requête.
    func forceRefresh() async {
        await apply(await loader.forceRefresh(departments: followedDepartments))
    }

    // MARK: Sélection

    func choose(_ selection: ScheduleSelection) {
        selectionStorage.save(selection)
        activate(selection)
    }

    private func activate(_ selection: ScheduleSelection) {
        // Si le dossier de cache est inaccessible, on garde tout en mémoire :
        // l'app reste utilisable, elle repartira du réseau au prochain lancement.
        let cache: any ScheduleCache = (try? FileScheduleCache()) ?? InMemoryScheduleCache()
        schedule = ScheduleStore(selection: selection, client: client, cache: cache)
        phase = .schedule(selection)
    }

}
