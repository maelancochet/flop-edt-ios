import SwiftUI
import FlopEDTKit

/// L'écran principal : bande de dates en haut, journée en dessous.
struct ScheduleScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let selection: ScheduleSelection

    @State private var selectedDate = DebugOverrides.initialDate ?? FlopCalendar.today()
    /// Indexé par (emploi du temps, semaine) et non par la semaine seule : une
    /// entrée téléchargée pour l'ancien groupe devient ainsi illisible, sans
    /// qu'aucun nettoyage n'ait à se produire au bon moment.
    @State private var schedules: [ScheduleCacheKey: WeekSchedule] = [:]
    @State private var error: APIError?
    @State private var durations: [String: Int] = [:]
    /// Le département auquel se rapportent les durées ci-dessus.
    @State private var durationsDepartment: String?
    @State private var showsUpdateNotice = false
    /// Identifie la dernière mise à jour signalée.
    ///
    /// Le bandeau s'efface au bout de trois secondes, par une tâche à part —
    /// attendre en ligne ajouterait ce délai au cycle de sondage. Le jeton évite
    /// qu'une tâche périmée éteigne le bandeau qu'une plus récente vient
    /// d'allumer.
    @State private var updateNoticeToken = 0
    @State private var destination: Destination?
    /// Instant où l'app a quitté le premier plan.
    ///
    /// `nil` tant qu'elle n'en est jamais partie : le premier passage à
    /// `.active` est celui du lancement, où `.task(id:)` vient déjà de charger.
    /// Le distinguer évite de télécharger la semaine deux fois à l'ouverture.
    @State private var leftForegroundAt: Date?

    private enum Destination: String, Identifiable {
        case settings, rooms, change
        var id: String { rawValue }
    }

    private var week: ISOWeek { ISOWeek(containing: selectedDate) }

    /// Identifie le couple (emploi du temps suivi, semaine affichée).
    private var key: ScheduleCacheKey { ScheduleCacheKey(selection: selection, week: week) }
    private var schedule: WeekSchedule? { schedules[key] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(selection: $selectedDate) {
                    schedules[ScheduleCacheKey(selection: selection, week: $0)]?.busyDays ?? []
                }
                Divider()
                dayContent
            }
            .navigationTitle(title)
            .navigationSubtitleIfAvailable(subtitle)
            // Comme l'original : le grand titre reste épinglé dans la barre,
            // aligné à gauche, au lieu d'un titre 17 pt centré.
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar { toolbar }
            .overlay(alignment: .top) { notices }
        }
        // La clé englobe la sélection : changer de groupe relance le chargement
        // et annule la boucle de sondage de l'ancien groupe, sans quoi la tâche
        // resterait accrochée à la semaine seule.
        .task(id: key) {
            await load(week)
            if let requested = DebugOverrides.initialScreen {
                destination = Destination(rawValue: requested)
            }
            // Puis on sonde tant que l'écran reste ouvert sur cette semaine.
            // La tâche est annulée au changement de semaine ou à la fermeture.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await poll()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                leftForegroundAt = .now
            case .active:
                guard let left = leftForegroundAt else { return }
                leftForegroundAt = nil
                let previous = week

                // iOS garde l'app en mémoire plusieurs jours. Sans ce
                // rattrapage, l'étudiant qui rouvre le lendemain matin retrouve
                // la journée de la veille : la semaine est bien retéléchargée,
                // mais le jour sélectionné ne bouge pas — et comme c'est la même
                // semaine ISO, le bouton « Aujourd'hui » ne s'affiche pas.
                if let today = FlopCalendar.dateAfterResume(selected: selectedDate, lastActive: left) {
                    selectedDate = today
                }

                // Changer de semaine relance `.task(id:)`, qui recharge seul.
                // Rester dans la même — le cas le plus courant, lundi vers mardi
                // — laisse la clé inchangée : c'est ici qu'il faut recharger.
                if ISOWeek(containing: selectedDate) == previous {
                    Task { await load(previous) }
                }
            default:
                break
            }
        }
        .sheet(item: $destination) { destination in
            Group {
                switch destination {
                case .settings:
                    SettingsView(selection: selection)
                case .rooms:
                    // Tous les départements : les salles de l'IUT sont partagées,
                    // et n'interroger que le sien revient à en annoncer libres
                    // qui sont prises.
                    FreeRoomsView(
                        department: selection.department,
                        departments: model.departments.map(\.abbrev),
                        durations: durations
                    )
                case .change:
                    ChangeSelectionView()
                }
            }
            // Même sans plusieurs hauteurs, la poignée annonce qu'on peut
            // refermer d'un glissement — le bouton n'est pas le seul chemin.
            .presentationDragIndicator(.visible)
        }
    }

    /// Le mois, et l'année seulement quand elle n'est pas l'année en cours.
    ///
    /// « Septembre 2026 » ne tient pas à côté de trois boutons : le titre ne
    /// dispose que d'un peu plus de la moitié de la largeur. L'année n'apporte
    /// rien tant qu'on consulte l'année en cours ; elle réapparaît d'elle-même
    /// dès qu'on franchit le nouvel an, c'est-à-dire quand elle devient utile.
    private var title: String {
        let shown = FlopCalendar.iso.component(.year, from: selectedDate)
        let current = FlopCalendar.iso.component(.year, from: .now)
        let formatter = shown == current ? DateFormatter.frenchMonthOnly : DateFormatter.frenchMonth
        return formatter.string(from: selectedDate).capitalizedFirst
    }

    /// Le numéro de semaine ISO — celui dont on parle à l'IUT.
    private var subtitle: String {
        "Semaine \(week.week)"
    }

    /// Sommes-nous sur la semaine en cours ?
    ///
    /// La bascule se fait à la semaine et non au jour : sélectionner mardi alors
    /// qu'on est vendredi ne doit pas escamoter les trois boutons.
    private var isOnCurrentWeek: Bool {
        week == ISOWeek.current()
    }

    /// Un seul groupe, dont le contenu se substitue.
    ///
    /// Sur la semaine en cours, les trois actions. Dès qu'on s'en éloigne, elles
    /// laissent la place au retour vers aujourd'hui — le groupe se transforme au
    /// lieu de s'allonger.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isOnCurrentWeek {
                Button("Salles libres", systemImage: "door.left.hand.open") {
                    destination = .rooms
                }
                Button("Changer d'emploi du temps", systemImage: "rectangle.2.swap") {
                    destination = .change
                }
                Button("Réglages", systemImage: "gearshape") {
                    destination = .settings
                }
            } else {
                Button("Aujourd'hui") {
                    withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                        selectedDate = FlopCalendar.today()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dayContent: some View {
        if let schedule {
            let courses = schedule.courses(on: selectedDate)
            if courses.isEmpty {
                EmptyDayView(date: selectedDate, weekIsEmpty: schedule.isEmpty)
            } else {
                DayTimeline(
                    date: selectedDate,
                    courses: courses,
                    durations: durations,
                    settings: model.timeSettings(for: selection.department),
                    isToday: FlopCalendar.iso.isDateInToday(selectedDate)
                )
            }
        } else if let error {
            LoadFailure(error: error) { await load(week) }
        } else {
            // Tant qu'il n'y a ni données ni erreur, on charge. Cette branche
            // rendait auparavant un `Color.clear`, visible comme un aplat blanc
            // le temps d'une image après un changement de groupe.
            VStack {
                Spacer()
                ProgressView().controlSize(.large)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        VStack(spacing: 6) {
            if let error, schedule != nil {
                Notice(text: error.errorDescription ?? "Hors ligne", tint: .orange, icon: "wifi.slash")
            }
            if showsUpdateNotice {
                Notice(text: "Emploi du temps mis à jour", tint: .green, icon: "arrow.triangle.2.circlepath")
            }
            // Un cours que le serveur a renvoyé mais qu'on n'a pas su lire est
            // écarté plutôt que de faire échouer la semaine entière. Le dire
            // vaut mieux que de le faire disparaître en silence.
            if let schedule, schedule.unreadableCourses > 0 {
                Notice(
                    text: schedule.unreadableCourses == 1
                        ? "1 cours n'a pas pu être lu"
                        : "\(schedule.unreadableCourses) cours n'ont pas pu être lus",
                    tint: .orange,
                    icon: "exclamationmark.triangle"
                )
            }
        }
        .padding(.top, 6)
        .animation(.snappy, value: showsUpdateNotice)
        .animation(.snappy, value: error)
    }

    // MARK: Chargement

    private func load(_ target: ISOWeek) async {
        guard let store = model.schedule else { return }
        let target = ScheduleCacheKey(selection: selection, week: target)

        // Remis à zéro avant tout `await` : sinon l'échec de la sélection
        // précédente reste affiché pendant le chargement de la nouvelle, et
        // l'écran montre « Chargement impossible » au lieu du compteur.
        error = nil

        // Les durées dépendent du département : elles doivent suivre s'il change.
        if durations.isEmpty || durationsDepartment != selection.department {
            durations = (try? await model.departmentData(selection.department))?.durationsByType ?? [:]
            durationsDepartment = selection.department
        }

        // Le cache s'affiche d'abord, le serveur ensuite — systématiquement.
        for await step in store.load(target.week) {
            switch step {
            case .cached(let value):
                schedules[target] = value
            case .fresh(let value):
                // Ne réanimer la vue que si le contenu a réellement changé.
                let shown = schedules[target]
                let changed = shown?.hasSameCourses(as: value) == false
                if changed || shown == nil {
                    withAnimation(.snappy) { schedules[target] = value }
                } else {
                    schedules[target] = value
                }
                // Le cache s'affiche d'abord, le serveur ensuite : quand les
                // deux diffèrent, l'écran change sous les yeux de l'utilisateur.
                // Le lui dire, comme le fait déjà le sondage — sans quoi une
                // correction légitime se lit comme un défaut d'affichage.
                // Le cas est tout sauf théorique : fin août, l'IUT régénère
                // l'année entière, et une semaine peut changer d'une minute
                // à l'autre.
                if changed { flashUpdateNotice() }
                error = nil
            case .failed(let failure, let stale):
                if let stale { schedules[target] = stale }
                error = failure
            }
        }

        await store.prefetch(around: target.week)
    }

    /// Sondage pendant que l'écran est ouvert : 70 octets, et rechargement
    /// seulement si la version a bougé. C'est ce qui couvre un cours déplacé
    /// en cours de journée.
    private func poll() async {
        guard let store = model.schedule else { return }
        if case .changed(let updated) = await store.checkForUpdate(week) {
            withAnimation(.snappy) { schedules[key] = updated }
            flashUpdateNotice()
        }
    }

    /// Signale que l'emploi du temps affiché vient d'être remplacé.
    private func flashUpdateNotice() {
        updateNoticeToken += 1
        let token = updateNoticeToken
        showsUpdateNotice = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard token == updateNoticeToken else { return }
            showsUpdateNotice = false
        }
    }
}

// MARK: - Journée vide

private struct EmptyDayView: View {
    let date: Date
    let weekIsEmpty: Bool

    var body: some View {
        VStack {
            Spacer()
            if let holiday = FrenchHolidays.name(on: date) {
                ContentUnavailableView(holiday, systemImage: "flag.fill", description: Text("Jour férié"))
            } else if weekIsEmpty {
                // L'API n'expose pas de calendrier scolaire : une semaine sans
                // aucun cours est le signal le plus fiable de vacances.
                ContentUnavailableView(
                    "Aucun cours cette semaine",
                    systemImage: "beach.umbrella",
                    description: Text("Semaine \(ISOWeek(containing: date).week)")
                )
            } else {
                ContentUnavailableView(
                    "Journée libre",
                    systemImage: "checkmark.circle",
                    description: Text("Aucun cours ce jour-là")
                )
            }
            Spacer()
        }
    }
}

private struct Notice: View {
    let text: String
    let tint: Color
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.gradient, in: .capsule)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
