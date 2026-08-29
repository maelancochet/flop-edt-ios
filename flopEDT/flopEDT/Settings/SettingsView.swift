import SwiftUI
import FlopEDTKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    let selection: ScheduleSelection
    @State private var isRefreshing = false

    private var path: GroupPath? {
        model.cachedDepartmentData(selection.department)
            .flatMap { selection.path(in: $0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Emploi du temps suivi") {
                    LabeledContent("Département", value: DepartmentStyle.title(for: selection.department))
                    LabeledContent("Promotion", value: promoName)
                    LabeledContent("Groupe", value: selection.group)
                    if let path {
                        LabeledContent("Hiérarchie", value: path.displayPath)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task {
                            isRefreshing = true
                            await model.forceRefresh()
                            isRefreshing = false
                        }
                    } label: {
                        HStack {
                            Text("Actualiser départements et groupes")
                            Spacer()
                            if isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(isRefreshing)
                } header: {
                    Text("Données")
                } footer: {
                    // Ce que l'app ne demande plus jamais à l'utilisateur de faire.
                    Text("""
                        Départements, promotions, groupes et durées de cours sont \
                        récupérés depuis flop!EDT et se mettent à jour tout seuls. \
                        L'emploi du temps, lui, est retéléchargé à chaque ouverture \
                        de l'application.
                        """)
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Source", value: "flopedt.iut-blagnac.fr")
                    // `.distantPast` marque un référentiel jamais confirmé par
                    // le serveur — l'instantané embarqué d'une première
                    // installation. Afficher « il y a 2 000 ans » n'aiderait pas.
                    if model.referential.fetchedAt != .distantPast {
                        LabeledContent(
                            "Référentiel",
                            value: model.referential.fetchedAt.formatted(
                                .relative(presentation: .named).locale(Locale(identifier: "fr_FR"))
                            )
                        )
                    }
                } header: {
                    Text("À propos")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private var promoName: String {
        model.cachedDepartmentData(selection.department)?
            .trainingPrograms.first { $0.abbrev == selection.promo }?
            .name ?? selection.promo
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
