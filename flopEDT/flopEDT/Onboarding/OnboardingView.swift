import SwiftUI
import FlopEDTKit

/// Le choix de l'emploi du temps : département, puis promo, puis groupe.
///
/// La descente dans les groupes est **récursive**, et c'est essentiel : la
/// profondeur varie de 1 niveau (LPMA, CS2) à 3 (INFO BUT2). La v1 imposait trois
/// écrans fixes et devait rattraper le coup par un `switch` sur le département.
/// Ici, un même écran se rappelle lui-même jusqu'à atteindre une feuille.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []

    /// Le même écran sert au premier lancement et au changement d'emploi du
    /// temps depuis la barre d'outils ; seule la possibilité d'annuler diffère.
    var isModal = false
    /// Appelé quand l'écran a fini son office, en mode modal.
    ///
    /// Le renvoi ne peut pas être fait par les vues poussées : à l'intérieur
    /// d'un `NavigationStack`, `@Environment(\.dismiss)` dépile la navigation
    /// au lieu de fermer la feuille. C'est donc la racine de la feuille qui
    /// ferme, via cette fermeture.
    var onFinish: (() -> Void)?

    enum Step: Hashable {
        case promos(department: String)
        /// `parents` est un chemin de **positions** dans l'arbre, pas de noms.
        /// Rien côté serveur n'interdit deux frères homonymes ; naviguer par
        /// nom choisirait alors la mauvaise branche, et la liste SwiftUI
        /// mélangerait ses lignes.
        case groups(department: String, promo: String, parents: [Int])
    }

    /// « Informatique · BUT1 · 1A », ou rien s'il n'y a pas encore de sélection.
    private var currentSummary: String? {
        guard let current = model.currentSelection else { return nil }
        return "\(DepartmentStyle.title(for: current.department)) · \(current.promo) · \(current.group)"
    }

    var body: some View {
        NavigationStack(path: $path) {
            DepartmentList(onSelect: { path.append(.promos(department: $0.abbrev)) })
                .navigationTitle("Emploi du temps")
                // Le rappel de l'emploi du temps suivi. En sous-titre plutôt
                // qu'en pied de liste : l'information compte, et une bottom
                // sheet n'a pas de hauteur à gaspiller. Absent au premier
                // lancement, où il n'y a rien à rappeler.
                .navigationSubtitleIfAvailable(currentSummary)
                // En feuille, un grand titre calé à gauche déséquilibre l'en-tête
                // face au seul bouton « Annuler ». Au premier lancement, en
                // revanche, l'écran occupe tout l'espace et mérite son grand titre.
                .navigationBarTitleDisplayMode(isModal ? .inline : .large)
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .promos(let department):
                        PromoList(department: department, path: $path)
                    case .groups(let department, let promo, let parents):
                        GroupList(
                            department: department, promo: promo,
                            parents: parents, path: $path, onFinish: onFinish
                        )
                    }
                }
                .toolbar {
                    if isModal {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annuler") { onFinish?() }
                        }
                    }
                }
        }
    }
}

// MARK: - Départements

private struct DepartmentList: View {
    @Environment(AppModel.self) private var model
    let onSelect: (Department) -> Void

    var body: some View {
        List {
            Section {
                ForEach(model.departments) { department in
                    Button {
                        onSelect(department)
                    } label: {
                        Label {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    let title = DepartmentStyle.title(for: department.abbrev)
                                    Text(title)
                                        .foregroundStyle(.primary)
                                    // Un département inconnu retombe sur son
                                    // abrégé : inutile de l'écrire deux fois.
                                    if title != department.abbrev {
                                        Text(department.abbrev)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if model.currentSelection?.department == department.abbrev {
                                    ActiveMark()
                                }
                            }
                        } icon: {
                            Image(systemName: DepartmentStyle.symbol(for: department.abbrev))
                                .foregroundStyle(.tint)
                        }
                    }
                }
            } header: {
                Text("Département")
            } footer: {
                Text("La liste est celle publiée par flop!EDT. Elle se met à jour toute seule.")
            }
        }
    }
}

// MARK: - Promos

private struct PromoList: View {
    @Environment(AppModel.self) private var model
    let department: String
    @Binding var path: [OnboardingView.Step]

    @State private var data: DepartmentReferential?
    @State private var error: APIError?

    var body: some View {
        Group {
            if let data {
                List {
                    Section {
                        // Seules les promos pourvues de groupes : une promo vide
                        // ne mènerait qu'à un écran sans issue.
                        ForEach(data.selectablePrograms) { program in
                            Button {
                                choose(program, in: data)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(program.name)
                                            .foregroundStyle(.primary)
                                        // La qualité des libellés varie d'un
                                        // département à l'autre : INFO annonce
                                        // « BUT Informatique première année »,
                                        // mais GIM et LPMA renvoient exactement
                                        // l'abrégé, et CS « BUT CS1 ». Répéter
                                        // l'abrégé n'apporterait alors rien.
                                        if !program.name.contains(program.abbrev) {
                                            Text(program.abbrev)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if isCurrent(program) {
                                        ActiveMark()
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Promotion")
                    } footer: {
                        // RT distingue BUT2 et BUT2A : ce ne sont pas des années
                        // d'étude mais des parcours, avec des emplois du temps
                        // différents.
                        Text("Les parcours en alternance ont leur propre emploi du temps.")
                    }
                }
            } else if let error {
                LoadFailure(error: error) { await load() }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .navigationTitle(DepartmentStyle.title(for: department))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// La promo suivie, à condition d'être dans le bon département.
    private func isCurrent(_ program: TrainingProgram) -> Bool {
        guard let current = model.currentSelection, current.department == department else { return false }
        return current.promo == program.abbrev
    }

    private func choose(_ program: TrainingProgram, in data: DepartmentReferential) {
        let roots = data.groupTree.roots(ofPromo: program.abbrev)
        // Une promo à racine unique n'a pas à faire choisir cette racine.
        if roots.count == 1, let root = roots.first, !root.isLeaf {
            path.append(.groups(department: department, promo: program.abbrev, parents: [0]))
        } else {
            path.append(.groups(department: department, promo: program.abbrev, parents: []))
        }
    }

    private func load() async {
        error = nil
        if let cached = model.cachedDepartmentData(department) {
            data = cached
        }
        do {
            data = try await model.departmentData(department)
        } catch let failure as APIError {
            if data == nil { error = failure }
        } catch {}
    }
}

// MARK: - Groupes

private struct GroupList: View {
    @Environment(AppModel.self) private var model
    let department: String
    let promo: String
    /// Le chemin déjà parcouru dans l'arbre, en positions depuis la racine.
    let parents: [Int]
    @Binding var path: [OnboardingView.Step]
    let onFinish: (() -> Void)?

    /// Le groupe qu'on vient de taper, le temps que la coche s'affiche.
    @State private var pending: String?

    private var data: DepartmentReferential? {
        model.cachedDepartmentData(department)
    }

    /// Une ligne de la liste.
    ///
    /// L'identité mêle la position et le nom : le nom seul ne suffit pas, deux
    /// frères pouvant en théorie porter le même — SwiftUI mélangerait alors les
    /// lignes et la sélection sauterait.
    private struct Row: Identifiable {
        let index: Int
        let node: GroupNode
        var id: String { "\(index)·\(node.name)" }
    }

    /// Descend l'arbre par positions : les nœuds à proposer, et les noms
    /// traversés pour y arriver.
    private var level: (nodes: [GroupNode], parentNames: [String]) {
        guard let data else { return ([], []) }
        var current = data.groupTree.roots(ofPromo: promo)
        var names: [String] = []
        for index in parents {
            guard current.indices.contains(index) else { return ([], []) }
            names.append(current[index].name)
            current = current[index].subgroups
        }
        return (current, names)
    }

    private var nodes: [GroupNode] { level.nodes }

    private var rows: [Row] {
        nodes.enumerated().map { Row(index: $0.offset, node: $0.element) }
    }

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    let node = row.node
                    Button {
                        select(node, at: row.index)
                    } label: {
                        HStack {
                            Text(node.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if node.isLeaf {
                                // La coche ne marque que le groupe réellement
                                // suivi. Elle figurait auparavant sur toutes les
                                // feuilles, où elle signifiait « fin de l'arbre »
                                // — ce qui se lisait comme « déjà sélectionné ».
                                if node.name == pending || node.name == currentGroup {
                                    ActiveMark()
                                }
                            } else {
                                Text("\(node.leaves.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } header: {
                Text(levelTitle)
            } footer: {
                Text(guidance)
            }
        }
        .navigationTitle(promo)
        // Le chemin parcouru, sans la racine : celle-ci porte un nom interne
        // (« CE ») qui ne dit rien à personne, et la promo est déjà dans le titre.
        .navigationSubtitleIfAvailable(pathSummary)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: pending)
    }

    /// Le type commun aux groupes listés — `TD`, `TP`… — tel que le département
    /// le nomme, ou `nil` si le niveau en mélange plusieurs.
    private var levelType: String? {
        model.referential.commonGroupTypeName(
            department: department,
            promo: promo,
            groups: nodes.map(\.name)
        )
    }

    /// « Groupe de TD » plutôt que « CE ».
    private var levelTitle: String {
        levelType.map { "Groupe de \($0)" } ?? "Groupe"
    }

    private var guidance: String {
        guard nodes.contains(where: \.isLeaf) else { return "Descendez jusqu'à votre groupe." }
        // Le libellé disait « groupe de TD » en dur, alors que le dernier niveau
        // est fait de TP dans les cinq départements.
        return levelType.map { "Choisissez votre groupe de \($0)." } ?? "Choisissez votre groupe."
    }

    private var pathSummary: String? {
        let trail = level.parentNames.dropFirst()
        return trail.isEmpty ? nil : trail.joined(separator: " › ")
    }

    /// Le groupe suivi, à condition d'être dans le bon département et la bonne
    /// promo — `1A` existe dans plusieurs promos.
    private var currentGroup: String? {
        guard let current = model.currentSelection,
              current.department == department,
              current.promo == promo
        else { return nil }
        return current.group
    }

    private func select(_ node: GroupNode, at index: Int) {
        guard node.isLeaf else {
            path.append(.groups(
                department: department,
                promo: promo,
                parents: parents + [index]
            ))
            return
        }
        // Un choix déjà en cours : on ignore les taps suivants.
        guard pending == nil else { return }

        // La coche s'affiche d'abord, l'écran se ferme ensuite. Sans ce court
        // délai, la feuille disparaît avant que l'utilisateur ait vu ce qu'il
        // venait de choisir.
        withAnimation(.snappy) { pending = node.name }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            model.choose(ScheduleSelection(department: department, promo: promo, group: node.name))
            onFinish?()
        }
    }
}

// MARK: - Échec

struct LoadFailure: View {
    let error: APIError
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Chargement impossible", systemImage: "wifi.exclamationmark")
        } description: {
            Text(error.errorDescription ?? "Une erreur est survenue.")
        } actions: {
            Button("Réessayer") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// La coche qui désigne l'élément suivi, à tous les niveaux de l'écran.
private struct ActiveMark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .accessibilityLabel("Sélectionné")
    }
}
