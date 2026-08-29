import SwiftUI
import FlopEDTKit

/// Les salles libres, à l'instant choisi.
///
/// Trié par temps de disponibilité décroissant : la question réelle n'est pas
/// « quelles salles sont libres » mais « où puis-je m'installer sans être délogé
/// dans dix minutes ». Les salles disponibles jusqu'au soir arrivent en tête.
struct FreeRoomsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    let department: String
    /// Tous les départements de l'IUT. Les salles sont partagées : un TD de CS
    /// occupe une salle que la table d'INFO déclare aussi, donc ne lire que son
    /// propre département revient à annoncer libres des salles prises.
    let departments: [String]
    let durations: [String: Int]

    @State private var moment: Date = .now
    @State private var occupancy: RoomOccupancy?
    @State private var isLoading = true
    @State private var error: APIError?
    @State private var showsBusy = false

    private var day: Weekday { Weekday(date: moment) }
    private var minute: Int { FlopCalendar.minutesSinceMidnight(of: moment) }

    var body: some View {
        NavigationStack {
            Group {
                if let occupancy {
                    list(occupancy)
                } else if isLoading {
                    ProgressView("Analyse des salles…").controlSize(.large)
                } else if let error {
                    LoadFailure(error: error) { await load() }
                }
            }
            .navigationTitle("Salles libres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            // Changer d'heure dans la journée ne coûte rien — tout est déjà en
            // mémoire. Changer de semaine, si.
            //
            // Un seul `.task(id:)` plutôt qu'un `.task` doublé d'un `.onChange` :
            // les deux lançaient des chargements concurrents, sans annulation ni
            // ordre, et c'est la réponse arrivée en dernier qui s'affichait —
            // pas celle de la semaine demandée. `.task(id:)` annule la
            // précédente et garantit l'ordre.
            .task(id: ISOWeek(containing: moment)) { await load() }
        }
    }

    private func list(_ occupancy: RoomOccupancy) -> some View {
        List {
            Section {
                DatePicker(
                    "Moment",
                    selection: $moment,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .environment(\.locale, Locale(identifier: "fr_FR"))

                if moment.timeIntervalSinceNow < -60 || moment.timeIntervalSinceNow > 60 {
                    Button("Revenir à maintenant") { moment = .now }
                }
            } footer: {
                // Toute la semaine est déjà téléchargée : changer d'heure ne
                // relance aucune requête.
                Text(coverage(occupancy))
            }

            let free = occupancy.freeRooms(on: day, at: minute)
            Section {
                if free.isEmpty {
                    Text("Aucune salle libre à cette heure.")
                        .foregroundStyle(.secondary)
                }
                ForEach(free) { room in
                    RoomRow(availability: room, minute: minute)
                }
            } header: {
                Text(count(free.count, "salle libre", "salles libres"))
            }

            let busy = occupancy.busyRooms(on: day, at: minute)
            Section(isExpanded: $showsBusy) {
                ForEach(busy) { room in
                    RoomRow(availability: room, minute: minute)
                }
            } header: {
                Text(count(busy.count, "salle occupée", "salles occupées"))
            }
        }
        .listStyle(.sidebar)
    }

    /// L'accord se fait à la main : l'inflexion automatique de SwiftUI demande
    /// un catalogue de localisation, absent d'un projet monolingue.
    private func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value > 1 ? plural : singular)"
    }

    /// Ce que le calcul a réellement pu voir.
    ///
    /// Un département injoignable ne vide pas l'écran, mais rend le résultat
    /// optimiste : certaines salles annoncées libres peuvent être prises. Mieux
    /// vaut le dire que de laisser croire à un décompte complet.
    private func coverage(_ occupancy: RoomOccupancy) -> String {
        guard !occupancy.missingDepartments.isEmpty else {
            return "Changer d'heure ne relance aucun téléchargement."
        }
        let missing = occupancy.missingDepartments.map(DepartmentStyle.title(for:)).joined(separator: ", ")
        return "Occupation de \(missing) indisponible : certaines salles annoncées libres peuvent être prises."
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            occupancy = try await model.rooms.occupancy(
                department: department,
                week: ISOWeek(containing: moment),
                durations: durations,
                departments: departments
            )
        } catch {
            let failure = APIError.wrapping(error)
            // Semaine changée en cours de route : `.task(id:)` a annulé la
            // précédente, il n'y a rien à signaler à l'utilisateur.
            guard !failure.isSilent else { return }
            self.error = failure
        }
        isLoading = false
    }
}

private struct RoomRow: View {
    let availability: RoomAvailability
    let minute: Int

    var body: some View {
        HStack {
            Image(systemName: availability.isFree ? "door.left.hand.open" : "door.left.hand.closed")
                .foregroundStyle(availability.isFree ? Color.green : Color.secondary)
                .frame(width: 24)

            Text(availability.room)
                .font(.body.weight(.medium))

            Spacer()

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        switch availability.status {
        case .free(let until):
            guard let until else { return "toute la journée" }
            let remaining = availability.status.remaining(from: minute) ?? 0
            return "jusqu'à \(until.asClockTime) (\(remaining.asDuration))"
        case .busy(let until, let reason):
            switch reason {
            case .course(let module, let type):
                return "\(module) \(type) — jusqu'à \(until.asClockTime)"
            case .unavailable:
                return "indisponible jusqu'à \(until.asClockTime)"
            }
        }
    }
}
