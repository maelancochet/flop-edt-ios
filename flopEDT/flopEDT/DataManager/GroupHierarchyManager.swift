import Foundation
import SwiftUI
import Combine

struct GroupNode: Codable {
    let parent: String?
    let promo: String?
    let promotxt: String?
    let row: Int?
    let name: String
    let buttxt: String?
    let children: [GroupNode]?

    init(parent: String? = nil, promo: String? = nil, promotxt: String? = nil,
         row: Int? = nil, name: String, buttxt: String? = nil, children: [GroupNode]? = nil) {
        self.parent = parent
        self.promo = promo
        self.promotxt = promotxt
        self.row = row
        self.name = name
        self.buttxt = buttxt
        self.children = children
    }
}

class GroupHierarchyManager: ObservableObject {
    @Published var departement: String = ""
    @Published var annee: String = ""
    @Published var groupe: String = ""
    @Published var result: [String] = []
    @Published var errorMessage: String = ""
    @Published var parent1: String = ""
    @Published var parent2: String = ""

    func handleStruct(for dept: String) -> [GroupNode] {
        switch dept {
        case "INFO": return getINFOStructure()
        case "CS": return getCSStructure()
        case "GIM": return getGIMStructure()
        case "RT": return getRTStructure()
        case "LPMA": return getLPMAStructure()
        default: return []
        }
    }

    func getGroupPath(departement: String, annee: String, groupe: String) -> [String] {
        self.departement = departement
        self.annee = annee
        self.groupe = groupe

        let data = handleStruct(for: departement)

        if data.isEmpty {
            errorMessage = "Département invalide"
            result = []
            parent1 = ""
            parent2 = ""
            return []
        }

        let promoSearch: String?
        switch departement {
        case "INFO", "RT": promoSearch = "BUT\(annee)"
        case "CS": promoSearch = "CS\(annee)"
        case "GIM": promoSearch = "GIM\(annee)"
        case "LPMA": promoSearch = "LPMA"
        default: promoSearch = nil
        }

        if let promo = promoSearch {
            for promoData in data {
                if promoData.promo == promo {
                    if let path = findGroup(in: [promoData], target: groupe) {
                        result = path
                        errorMessage = ""
                        extractParents(from: path)
                        return path
                    }
                }
            }
        }

        if let path = findGroup(in: data, target: groupe) {
            result = path
            errorMessage = ""
            extractParents(from: path)
            return path
        } else {
            result = []
            errorMessage = "Groupe non trouvé"
            parent1 = ""
            parent2 = ""
            return []
        }
    }

    private func extractParents(from path: [String]) {
        if path.count >= 4 {
            parent1 = path[1]
            parent2 = path[2]
        } else if path.count == 3 {
            parent1 = path[0]
            parent2 = path[1]
        } else if path.count == 2 {
            parent1 = path[0]
            parent2 = ""
        } else {
            parent1 = ""
            parent2 = ""
        }
    }

    func getGroupPath() {
        _ = getGroupPath(departement: departement, annee: annee, groupe: groupe)
    }

    private func findGroup(in nodes: [GroupNode], target: String, path: [String] = []) -> [String]? {
        for node in nodes {
            let currentPath = path + [node.name]

            if node.name == target {
                return currentPath
            }

            if let children = node.children, !children.isEmpty {
                if let result = findGroup(in: children, target: target, path: currentPath) {
                    return result
                }
            }
        }
        return nil
    }

    // TODO: Charger ces structures depuis l'API au lieu de les hardcoder

    private func getINFOStructure() -> [GroupNode] {
        return [
            GroupNode(parent: "null", promo: "BUT1", promotxt: "BUT1", row: 0, name: "CE", buttxt: "BUT1", children: [
                GroupNode(parent: "CE", name: "1", children: [
                    GroupNode(parent: "1", name: "1A"),
                    GroupNode(parent: "1", name: "1B")
                ]),
                GroupNode(parent: "CE", name: "2", children: [
                    GroupNode(parent: "2", name: "2A"),
                    GroupNode(parent: "2", name: "2B")
                ]),
                GroupNode(parent: "CE", name: "3", children: [
                    GroupNode(parent: "3", name: "3A"),
                    GroupNode(parent: "3", name: "3B")
                ]),
                GroupNode(parent: "CE", name: "4", children: [
                    GroupNode(parent: "4", name: "4A"),
                    GroupNode(parent: "4", name: "4B")
                ])
            ]),
            GroupNode(parent: "null", promo: "BUT2", promotxt: "BUT2", row: 0, name: "CE", buttxt: "BUT2", children: [
                GroupNode(parent: "CE", name: "12", children: [
                    GroupNode(parent: "12", name: "1", children: [
                        GroupNode(parent: "1", name: "1A"),
                        GroupNode(parent: "1", name: "1B")
                    ]),
                    GroupNode(parent: "12", name: "2", children: [
                        GroupNode(parent: "2", name: "2A"),
                        GroupNode(parent: "2", name: "2B")
                    ])
                ]),
                GroupNode(parent: "CE", name: "3", children: [
                    GroupNode(parent: "3", name: "3A")
                ])
            ]),
            GroupNode(parent: "null", promo: "BUT3", promotxt: "BUT3", row: 0, name: "CE", buttxt: "BUT3", children: [])
        ]
    }

    private func getCSStructure() -> [GroupNode] {
        return [
            GroupNode(parent: "null", promo: "CS1", promotxt: "CS1", row: 0, name: "CS1", children: [
                GroupNode(parent: "CS1", name: "1G1", children: [
                    GroupNode(parent: "1G1", name: "1GA"),
                    GroupNode(parent: "1G1", name: "1GB1")
                ]),
                GroupNode(parent: "CS1", name: "1G2", children: [
                    GroupNode(parent: "1G2", name: "1GB2"),
                    GroupNode(parent: "1G2", name: "1GC")
                ])
            ]),
            GroupNode(parent: "null", promo: "CS2", promotxt: "CS2", row: 0, name: "CS2", children: [
                GroupNode(parent: "CS2", name: "2FA"),
                GroupNode(parent: "CS2", name: "2FI", children: [
                    GroupNode(parent: "2FI", name: "2GA"),
                    GroupNode(parent: "2FI", name: "2GB")
                ])
            ]),
            GroupNode(parent: "null", promo: "CS3", promotxt: "CS3", row: 0, name: "CS3", children: [
                GroupNode(parent: "CS3", name: "3FA", children: [
                    GroupNode(parent: "3FA", name: "3FA1"),
                    GroupNode(parent: "3FA", name: "3FA2")
                ]),
                GroupNode(parent: "CS3", name: "3FI")
            ])
        ]
    }

    private func getGIMStructure() -> [GroupNode] {
        return [
            GroupNode(parent: "null", promo: "GIM1", promotxt: "GIM1", row: 0, name: "GIM1", children: [
                GroupNode(parent: "GIM1", name: "1TD1", children: [
                    GroupNode(parent: "1TD1", name: "1A"),
                    GroupNode(parent: "1TD1", name: "1B")
                ]),
                GroupNode(parent: "GIM1", name: "1TD2", children: [
                    GroupNode(parent: "1TD2", name: "1C"),
                    GroupNode(parent: "1TD2", name: "1D")
                ])
            ]),
            GroupNode(parent: "null", promo: "GIM2", promotxt: "GIM2", row: 0, name: "GIM2", children: [
                GroupNode(parent: "GIM2", name: "2TD1", children: [
                    GroupNode(parent: "2TD1", name: "2A"),
                    GroupNode(parent: "2TD1", name: "2B")
                ]),
                GroupNode(parent: "GIM2", name: "2TD2", children: [
                    GroupNode(parent: "2TD2", name: "2C"),
                    GroupNode(parent: "2TD2", name: "2D")
                ])
            ]),
            GroupNode(parent: "null", promo: "GIM3", promotxt: "GIM3", row: 0, name: "GIM3", children: [
                GroupNode(parent: "GIM3", name: "3TD1", children: [
                    GroupNode(parent: "3TD1", name: "3A")
                ]),
                GroupNode(parent: "GIM3", name: "3TD2", children: [
                    GroupNode(parent: "3TD2", name: "3B"),
                    GroupNode(parent: "3TD2", name: "3C")
                ])
            ])
        ]
    }

    private func getRTStructure() -> [GroupNode] {
        return [
            GroupNode(parent: "null", promo: "BUT1", promotxt: "BUT1", row: 0, name: "BUT1", children: [
                GroupNode(parent: "BUT1", name: "1G1", children: [
                    GroupNode(parent: "1G1", name: "1A"),
                    GroupNode(parent: "1G1", name: "1B")
                ]),
                GroupNode(parent: "BUT1", name: "1G2", children: [
                    GroupNode(parent: "1G2", name: "1C"),
                    GroupNode(parent: "1G2", name: "1D")
                ]),
                GroupNode(parent: "BUT1", name: "1G3", children: [
                    GroupNode(parent: "1G3", name: "1E"),
                    GroupNode(parent: "1G3", name: "1F")
                ])
            ]),
            GroupNode(parent: "null", promo: "BUT2", promotxt: "BUT2", row: 0, name: "BUT2", children: [
                GroupNode(parent: "BUT2", name: "2G1", children: [
                    GroupNode(parent: "2G1", name: "2A"),
                    GroupNode(parent: "2G1", name: "2B")
                ]),
                GroupNode(parent: "BUT2", name: "2G2", children: [
                    GroupNode(parent: "2G2", name: "2C")
                ])
            ]),
            GroupNode(parent: "null", promo: "BUT2A", promotxt: "BUT2A", row: 0, name: "BUT2A", children: [
                GroupNode(parent: "BUT2A", name: "2G1a", children: [
                    GroupNode(parent: "2G1a", name: "2Aa")
                ])
            ]),
            GroupNode(parent: "null", promo: "BUT3", promotxt: "BUT3", row: 0, name: "BUT3", children: [
                GroupNode(parent: "BUT3", name: "3G1", children: [
                    GroupNode(parent: "3G1", name: "3A"),
                    GroupNode(parent: "3G1", name: "3B")
                ])
            ]),
            GroupNode(parent: "null", promo: "BUT3A", promotxt: "BUT3A", row: 0, name: "BUT3A", children: [
                GroupNode(parent: "BUT3A", name: "3G1a", children: [
                    GroupNode(parent: "3G1a", name: "3Aa"),
                    GroupNode(parent: "3G1a", name: "3Ba")
                ])
            ])
        ]
    }

    private func getLPMAStructure() -> [GroupNode] {
        return [
            GroupNode(parent: "null", promo: "LPMA", promotxt: "LPMA", row: 0, name: "LPMA", children: [
                GroupNode(parent: "LPMA", name: "TP1"),
                GroupNode(parent: "LPMA", name: "TP2")
            ])
        ]
    }
}

struct GroupSearchView: View {
    @StateObject private var manager = GroupHierarchyManager()

    var body: some View {
        Form {
            Section("Recherche de groupe") {
                Picker("Département", selection: $manager.departement) {
                    Text("INFO").tag("INFO")
                    Text("CS").tag("CS")
                    Text("GIM").tag("GIM")
                    Text("RT").tag("RT")
                    Text("LPMA").tag("LPMA")
                }

                TextField("Année", text: $manager.annee)
                    .keyboardType(.numberPad)

                TextField("Groupe", text: $manager.groupe)
            }

            Section {
                Button("Rechercher") {
                    manager.getGroupPath()
                }
            }

            if !manager.result.isEmpty {
                Section("Résultat") {
                    Text("Chemin: \(manager.result.joined(separator: " > "))")
                        .font(.caption)

                    ForEach(Array(manager.result.dropLast().enumerated()), id: \.offset) { index, parent in
                        Text("Niveau \(index): \(parent)")
                    }
                }
            }

            if !manager.errorMessage.isEmpty {
                Section {
                    Text(manager.errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Recherche de groupe")
    }
}

#Preview {
    GroupSearchView()
}
