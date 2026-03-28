import SwiftUI

struct Departement: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var image: String
    var title: String
    var code: String
}

struct Period: Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var value: String
    var number: Int
}

struct Groupes: Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var departementCode: String
    var annee: String
    var trainprog: String
}

let departements: [Departement] = [
    .init(image: "pc", title: "Informatique", code: "INFO"),
    .init(image: "person.2.fill", title: "Carrières Sociales", code: "CS"),
    .init(image: "powercord.fill", title: "Génie Industriel et Maintenance", code: "GIM"),
    .init(image: "network", title: "Réseaux et Télécommunications", code: "RT"),
    .init(image: "airplane", title: "LP Maintenance Aéronautique", code: "LPMA"),
]

let periods: [Period] = [
    .init(title: "1ère année", value: "1re", number: 1),
    .init(title: "2e année", value: "2e", number: 2),
    .init(title: "3e année", value: "3e", number: 3),
]

// TODO: Charger depuis l'API au lieu de hardcoder
let allGroupes: [Groupes] = [
    // INFO
    .init(title: "1A", departementCode: "INFO", annee: "1re", trainprog: "BUT1"),
    .init(title: "1B", departementCode: "INFO", annee: "1re", trainprog: "BUT1"),
    .init(title: "2A", departementCode: "INFO", annee: "1re", trainprog: "BUT1"),
    .init(title: "2B", departementCode: "INFO", annee: "1re", trainprog: "BUT1"),
    .init(title: "3A", departementCode: "INFO", annee: "1re", trainprog: "BUT1"),
    .init(title: "3B", departementCode: "INFO", annee: "1re", trainprog: "BUT1"),
    .init(title: "4A", departementCode: "INFO", annee: "1re", trainprog: "BUT1"),
    .init(title: "4B", departementCode: "INFO", annee: "1re", trainprog: "BUT1"),
    .init(title: "1A", departementCode: "INFO", annee: "2e", trainprog: "BUT2"),
    .init(title: "1B", departementCode: "INFO", annee: "2e", trainprog: "BUT2"),
    .init(title: "2A", departementCode: "INFO", annee: "2e", trainprog: "BUT2"),
    .init(title: "2B", departementCode: "INFO", annee: "2e", trainprog: "BUT2"),
    .init(title: "3A", departementCode: "INFO", annee: "2e", trainprog: "BUT2"),
    .init(title: "1A", departementCode: "INFO", annee: "3e", trainprog: "BUT3"),
    .init(title: "1B", departementCode: "INFO", annee: "3e", trainprog: "BUT3"),
    .init(title: "2A", departementCode: "INFO", annee: "3e", trainprog: "BUT3"),
    .init(title: "3A", departementCode: "INFO", annee: "3e", trainprog: "BUT3"),
    .init(title: "3B", departementCode: "INFO", annee: "3e", trainprog: "BUT3"),

    // CS
    .init(title: "1GA", departementCode: "CS", annee: "1re", trainprog: "CS1"),
    .init(title: "1GB1", departementCode: "CS", annee: "1re", trainprog: "CS1"),
    .init(title: "1GB2", departementCode: "CS", annee: "1re", trainprog: "CS1"),
    .init(title: "1GC", departementCode: "CS", annee: "1re", trainprog: "CS1"),
    .init(title: "2FA", departementCode: "CS", annee: "2e", trainprog: "CS2"),
    .init(title: "2GA", departementCode: "CS", annee: "2e", trainprog: "CS2"),
    .init(title: "2GB", departementCode: "CS", annee: "2e", trainprog: "CS2"),
    .init(title: "3FA1", departementCode: "CS", annee: "3e", trainprog: "CS3"),
    .init(title: "3FA2", departementCode: "CS", annee: "3e", trainprog: "CS3"),
    .init(title: "3FI", departementCode: "CS", annee: "3e", trainprog: "CS3"),

    // GIM
    .init(title: "1A", departementCode: "GIM", annee: "1re", trainprog: "GIM1"),
    .init(title: "1B", departementCode: "GIM", annee: "1re", trainprog: "GIM1"),
    .init(title: "1C", departementCode: "GIM", annee: "1re", trainprog: "GIM1"),
    .init(title: "1D", departementCode: "GIM", annee: "1re", trainprog: "GIM1"),
    .init(title: "2A", departementCode: "GIM", annee: "2e", trainprog: "GIM2"),
    .init(title: "2B", departementCode: "GIM", annee: "2e", trainprog: "GIM2"),
    .init(title: "2C", departementCode: "GIM", annee: "2e", trainprog: "GIM2"),
    .init(title: "2D", departementCode: "GIM", annee: "2e", trainprog: "GIM2"),
    .init(title: "3A", departementCode: "GIM", annee: "3e", trainprog: "GIM3"),
    .init(title: "3B", departementCode: "GIM", annee: "3e", trainprog: "GIM3"),
    .init(title: "3C", departementCode: "GIM", annee: "3e", trainprog: "GIM3"),

    // RT
    .init(title: "1A", departementCode: "RT", annee: "1re", trainprog: "BUT1"),
    .init(title: "1B", departementCode: "RT", annee: "1re", trainprog: "BUT1"),
    .init(title: "1C", departementCode: "RT", annee: "1re", trainprog: "BUT1"),
    .init(title: "1D", departementCode: "RT", annee: "1re", trainprog: "BUT1"),
    .init(title: "1E", departementCode: "RT", annee: "1re", trainprog: "BUT1"),
    .init(title: "1F", departementCode: "RT", annee: "1re", trainprog: "BUT1"),
    .init(title: "2A", departementCode: "RT", annee: "2e", trainprog: "BUT2"),
    .init(title: "2B", departementCode: "RT", annee: "2e", trainprog: "BUT2"),
    .init(title: "2C", departementCode: "RT", annee: "2e", trainprog: "BUT2"),
    .init(title: "2Aa", departementCode: "RT", annee: "2e", trainprog: "BUT2A"),
    .init(title: "3A", departementCode: "RT", annee: "3e", trainprog: "BUT3"),
    .init(title: "3B", departementCode: "RT", annee: "3e", trainprog: "BUT3"),
    .init(title: "3Aa", departementCode: "RT", annee: "3e", trainprog: "BUT3A"),
    .init(title: "3Ba", departementCode: "RT", annee: "3e", trainprog: "BUT3A"),

    // LPMA
    .init(title: "TP1", departementCode: "LPMA", annee: "1re", trainprog: "LPMA"),
    .init(title: "TP2", departementCode: "LPMA", annee: "1re", trainprog: "LPMA"),
]

enum CurrentView {
    case departements
    case periods
    case groupes
}

struct TrayView: View {
    var animation: Animation

    @State private var currentView: CurrentView = .departements
    @State private var selectedDepartement: Departement?
    @State private var selectedPeriod: Period?
    @State private var selectedGroupes: Groupes?
    @Environment(\.dismiss) var dismiss

    @AppStorage(StorageKeys.departement) var departementtodownload: String = ""
    @State private var isEDTDownloaded = false
    @AppStorage(StorageKeys.trainprog) var trainprog: String = ""
    @AppStorage(StorageKeys.filtreCM) var filtreCM: String = ""
    @AppStorage(StorageKeys.filtreGroupe) var filtreGroupe: String = ""
    @AppStorage(StorageKeys.filtreSousGroupe) var filtreSousGroupe: String = ""
    @AppStorage(StorageKeys.yearhome) var yearhome: String = ""
    @AppStorage(StorageKeys.showTrayView) var showTrayView: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                switch currentView {
                case .departements:
                    View1()
                        .geometryGroup()
                        .transition(.blurReplace(.upUp))
                case .periods:
                    View2()
                        .geometryGroup()
                        .transition(.blurReplace(.downUp))
                case .groupes:
                    View3()
                        .geometryGroup()
                        .transition(.blurReplace(.downUp))
                }
            }
            .geometryGroup()

            if shouldShowSaveButton {
                Button {
                    saveSelection()
                    yearhome = String(selectedPeriod?.number ?? 0)
                } label: {
                    HStack(spacing: 8) {
                        if !isEDTDownloaded {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                        }

                        Text(isEDTDownloaded ? "Choisir L'Emploi du Temps" : "Téléchargement en cours...")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(isEDTDownloaded ? Color.blue : Color.gray, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!isEDTDownloaded)
                .opacity(isEDTDownloaded ? 1.0 : 0.7)
                .padding(.top, 15)
                .geometryGroup()
            }
        }
        .padding([.horizontal, .top], 20)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var shouldShowSaveButton: Bool {
        switch currentView {
        case .departements:
            return false
        case .periods:
            return selectedPeriod != nil && availableGroupes.isEmpty
        case .groupes:
            return selectedGroupes != nil
        }
    }

    private var availablePeriods: [Period] {
        guard let selectedDepartement = selectedDepartement else { return [] }
        let years = Set(
            allGroupes
                .filter { $0.departementCode == selectedDepartement.code }
                .map { $0.annee }
        )
        return periods.filter { years.contains($0.value) }
    }

    private var availableGroupes: [Groupes] {
        guard let selectedDepartement = selectedDepartement,
              let selectedPeriod = selectedPeriod else {
            return []
        }
        return allGroupes.filter { groupe in
            groupe.departementCode == selectedDepartement.code &&
            groupe.annee == selectedPeriod.value
        }
    }

    @ViewBuilder
    func View1() -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Sélection du Département")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer(minLength: 0)

                Button {
                    Task { await ScheduleDataManager.shared.clearCache() }
                    dismiss()
                    let generator = UIImpactFeedbackGenerator(style: .soft)
                    generator.impactOccurred()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.gray, Color.primary.opacity(0.1))
                }
            }
            .padding(.bottom, 25)

            Text("Choisissez votre département d'étude")
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
                .padding(.bottom, 20)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 15), count: 1)
            LazyVGrid(columns: columns, spacing: 15) {
                ForEach(departements) { departement in
                    let isSelected: Bool = selectedDepartement?.id == departement.id

                    HStack(spacing: 12) {
                        Image(systemName: departement.image)
                            .font(.title2)
                            .foregroundStyle(isSelected ? .blue : .primary)
                            .frame(width: 30)

                        Text(departement.title)
                            .font(.system(size: 16, weight: .medium))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(isSelected ? .blue : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill((isSelected ? Color.blue : Color.gray).opacity(isSelected ? 0.15 : 0.08))
                            .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.snappy) {
                            selectedDepartement = isSelected ? nil : departement

                            let generator = UIImpactFeedbackGenerator(style: .soft)
                            generator.impactOccurred()

                            if !isSelected {
                                isEDTDownloaded = false
                                Task {
                                    do {
                                        try await ScheduleDataManager.shared.loadCurrentAndUpcomingWeeks(dept: departement.code)
                                        await MainActor.run {
                                            isEDTDownloaded = true
                                            }
                                    } catch {
                                        await MainActor.run {
                                            isEDTDownloaded = false
                                        }
                                    }
                                }

                                selectedPeriod = nil
                                selectedGroupes = nil

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                    withAnimation(animation) {
                                        currentView = .periods
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func View2() -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Sélection de l'année d'étude")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    withAnimation(animation) {
                        Task { await ScheduleDataManager.shared.clearCache() }
                        isEDTDownloaded = false
                        currentView = .departements
                        let generator = UIImpactFeedbackGenerator(style: .soft)
                        generator.impactOccurred()
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                        .foregroundStyle(.gray, Color.primary.opacity(0.1))
                }
            }
            .padding(.bottom, 25)

            Text("Choisissez l'année correspondant à \nvotre période d'étude")
                .multilineTextAlignment(.center)
                .foregroundStyle(.gray)
                .padding(.bottom, 20)

            let columns = availablePeriods.count == 1 ? 1 : min(availablePeriods.count, 3)
            LazyVGrid(columns: Array(repeating: GridItem(), count: columns), spacing: 15) {
                ForEach(availablePeriods) { period in
                    let isSelected = selectedPeriod?.id == period.id
                    VStack(spacing: 6) {
                        Text(period.value)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Année")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill((isSelected ? Color.blue : Color.gray).opacity(isSelected ? 0.15 : 0.08))
                            .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)

                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(animation) {
                            selectedPeriod = isSelected ? nil : period
                            selectedGroupes = nil

                            let generator = UIImpactFeedbackGenerator(style: .soft)
                            generator.impactOccurred()

                            if !isSelected {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                    let groupesForSelection = allGroupes.filter { groupe in
                                        groupe.departementCode == selectedDepartement?.code &&
                                        groupe.annee == period.value
                                    }

                                    if !groupesForSelection.isEmpty {
                                        withAnimation(animation) {
                                            currentView = .groupes
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func View3() -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Sélection du Groupe")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer(minLength: 0)

                Button {
                    withAnimation(animation) {
                        currentView = .periods
                        let generator = UIImpactFeedbackGenerator(style: .soft)
                        generator.impactOccurred()
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                        .foregroundStyle(.gray, Color.primary.opacity(0.1))
                }
            }
            .padding(.bottom, 25)

            if availableGroupes.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 50))
                        .foregroundStyle(.gray)

                    Text("Aucun groupe disponible")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Ce département et cette année n'ont pas de groupes séparés")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.gray)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Choisissez votre groupe de classe")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray)
                    .padding(.bottom, 20)
                    .fixedSize(horizontal: false, vertical: true)

                let columns = availableGroupes.count == 1 ? 1 : min(availableGroupes.count, 2)
                LazyVGrid(columns: Array(repeating: GridItem(), count: columns), spacing: 15) {
                    ForEach(availableGroupes) { groupe in
                        let isSelected = selectedGroupes?.id == groupe.id

                        VStack(spacing: 6) {
                            Text(groupe.title)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Groupe")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill((isSelected ? Color.blue : Color.gray).opacity(isSelected ? 0.15 : 0.08))
                                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                        }
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(animation) {
                                selectedGroupes = isSelected ? nil : groupe

                                let generator = UIImpactFeedbackGenerator(style: .soft)
                                generator.impactOccurred()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func saveSelection() {
        guard isEDTDownloaded else { return }

        guard let dept = selectedDepartement,
              let period = selectedPeriod else {
            return
        }

        let annee = String(period.number)
        let groupe = selectedGroupes?.title ?? ""

        let manager = GroupHierarchyManager()
        let path = manager.getGroupPath(
            departement: dept.code,
            annee: annee,
            groupe: groupe
        )

        trainprog = selectedGroupes?.trainprog ?? ""
        departementtodownload = dept.code

        // Chaque département a une hiérarchie de groupes différente
        switch dept.code {
        case "INFO", "RT":
            filtreCM = manager.parent1.isEmpty ? path.first ?? "" : manager.parent1
            filtreGroupe = manager.parent2.isEmpty ? "" : manager.parent2
            filtreSousGroupe = selectedGroupes?.title ?? ""

        case "CS", "GIM":
            if path.count >= 3 {
                filtreCM = path[0]
                filtreGroupe = path[1]
                filtreSousGroupe = path.last ?? ""
            } else if path.count == 2 {
                filtreCM = path[0]
                filtreGroupe = ""
                filtreSousGroupe = path[1]
            } else {
                filtreCM = path.first ?? ""
                filtreGroupe = ""
                filtreSousGroupe = ""
            }

        case "LPMA":
            filtreCM = "LPMA"
            filtreGroupe = ""
            filtreSousGroupe = selectedGroupes?.title ?? ""

        default:
            filtreCM = manager.parent1
            filtreGroupe = manager.parent2
            filtreSousGroupe = selectedGroupes?.title ?? ""
        }

        showTrayView = false

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
