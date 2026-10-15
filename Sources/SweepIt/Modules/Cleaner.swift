import SwiftUI

// MARK: - Règles

struct CleanCategory: Identifiable {
    let id: String
    let title: String
    let icon: String
    let detail: String
    let info: String
    var items: [FileEntry]
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct CleanerRule {
    enum Mode { case children, whole }

    let id: String
    let title: String
    let icon: String
    let detail: String
    let info: String
    /// Chemins relatifs au dossier personnel.
    let paths: [String]
    let mode: Mode
    var excludeNames: Set<String> = []
    var excludePrefixes: [String] = []

    func scan() -> CleanCategory {
        var items: [FileEntry] = []
        for p in paths {
            let base = Safety.home.appendingPathComponent(p)
            guard FS.exists(base) else { continue }
            let targets = mode == .children ? FS.children(base) : [base]
            for t in targets {
                let n = t.lastPathComponent
                if excludeNames.contains(n) || excludePrefixes.contains(where: { n.hasPrefix($0) }) { continue }
                let size = FS.allocatedSize(t)
                if size > 0 { items.append(FileEntry(url: t, size: size)) }
            }
        }
        items.sort { $0.size > $1.size }
        return CleanCategory(id: id, title: title, icon: icon, detail: detail, info: info, items: items)
    }

    static let browserCacheNames: Set<String> = ["Google", "BraveSoftware", "Microsoft Edge", "Firefox",
                                                 "Arc", "company.thebrowser.Browser"]

    static let all: [CleanerRule] = [
        CleanerRule(id: "caches", title: "Fichiers temporaires des apps", icon: "archivebox",
                    detail: "Des copies que les apps gardent pour aller plus vite.",
                    info: "Les applications stockent des fichiers temporaires (images, morceaux de téléchargements…) pour démarrer plus vite. Si on les supprime, elles les recréent quand elles en ont besoin. Une app peut juste être un peu plus lente la première fois après le nettoyage.",
                    paths: ["Library/Caches"], mode: .children,
                    excludeNames: browserCacheNames, excludePrefixes: ["com.apple."]),
        CleanerRule(id: "logs", title: "Journaux d'activité", icon: "doc.text",
                    detail: "Le « carnet de bord » des apps, utile surtout en cas de panne.",
                    info: "Les apps notent ce qu'elles font dans des fichiers journaux. C'est pratique pour qu'un technicien comprenne un plantage, mais vous n'en avez pas besoin au quotidien.",
                    paths: ["Library/Logs"], mode: .children),
        CleanerRule(id: "browsers", title: "Mémoire des navigateurs", icon: "globe",
                    detail: "Pages et images de sites déjà visités (Chrome, Firefox, Arc…).",
                    info: "Votre navigateur garde une copie des sites visités pour les afficher plus vite. Les supprimer ne touche ni à vos favoris, ni à vos mots de passe, ni à votre historique. Pensez à fermer le navigateur avant de nettoyer.",
                    paths: ["Library/Caches/Google/Chrome", "Library/Caches/BraveSoftware",
                            "Library/Caches/Microsoft Edge", "Library/Caches/Firefox",
                            "Library/Caches/Arc", "Library/Caches/company.thebrowser.Browser"],
                    mode: .whole),
        CleanerRule(id: "xcode", title: "Fichiers de création d'apps (Xcode)", icon: "hammer",
                    detail: "Concerne seulement ceux qui programment des apps.",
                    info: "Xcode est l'outil d'Apple pour créer des applications. Il accumule des fichiers de travail qui peuvent peser des dizaines de Go. Ils sont recréés automatiquement au besoin. Si vous ne programmez pas, cette catégorie n'apparaîtra sans doute pas.",
                    paths: ["Library/Developer/Xcode/DerivedData",
                            "Library/Developer/Xcode/iOS DeviceSupport",
                            "Library/Developer/Xcode/watchOS DeviceSupport"],
                    mode: .children),
        CleanerRule(id: "xcode-sim", title: "Simulateur d'iPhone", icon: "iphone",
                    detail: "Fichiers temporaires du simulateur d'Xcode.",
                    info: "Le simulateur permet aux développeurs de tester une app comme sur un vrai iPhone. Ces fichiers temporaires sont recréés à la prochaine utilisation.",
                    paths: ["Library/Developer/CoreSimulator/Caches"], mode: .whole),
        CleanerRule(id: "dev", title: "Outils de programmation", icon: "shippingbox",
                    detail: "Téléchargements mis de côté par npm, Gradle ou Cargo.",
                    info: "Ces outils gardent une copie de tout ce qu'ils téléchargent pour ne pas le refaire. S'ils en ont à nouveau besoin, ils le retéléchargent simplement.",
                    paths: [".npm/_cacache", ".gradle/caches", ".cargo/registry/cache"], mode: .whole),
    ]
}

// MARK: - Modèle

enum CheckState {
    case none, some, all
    var symbol: String {
        switch self {
        case .none: "square"
        case .some: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}

@Observable @MainActor
final class CleanerModel {
    var categories: [CleanCategory] = []
    var selected: Set<URL> = []
    var isScanning = false
    var hasScanned = false
    var report: TrashReport?

    private var allItems: [FileEntry] { categories.flatMap(\.items) }
    var selectedItems: [FileEntry] { allItems.filter { selected.contains($0.url) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() {
        isScanning = true
        Task {
            let cats = await Task.detached(priority: .userInitiated) {
                CleanerRule.all.map { $0.scan() }
            }.value
            categories = cats.filter { !$0.items.isEmpty }
            selected = Set(categories.flatMap(\.items).map(\.url))
            isScanning = false
            hasScanned = true
        }
    }

    func clean() {
        report = Trash.move(selectedItems.map { ($0.url, $0.size) })
        scan()
    }

    func state(_ cat: CleanCategory) -> CheckState {
        let n = cat.items.filter { selected.contains($0.url) }.count
        return n == 0 ? .none : (n == cat.items.count ? .all : .some)
    }

    func toggle(_ cat: CleanCategory) {
        let urls = cat.items.map(\.url)
        if state(cat) == .all { selected.subtract(urls) } else { selected.formUnion(urls) }
    }

    func binding(_ url: URL) -> Binding<Bool> {
        Binding(get: { self.selected.contains(url) },
                set: { if $0 { self.selected.insert(url) } else { self.selected.remove(url) } })
    }
}

// MARK: - Vue

struct CleanerView: View {
    @Bindable var model: CleanerModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Nettoyage système",
                         subtitle: "Retirez les fichiers inutiles qui encombrent votre Mac.",
                         icon: "sparkles") {
                Button { model.scan() } label: {
                    Label(model.hasScanned ? "Réanalyser" : "Analyser", systemImage: "magnifyingglass")
                }
                .controlSize(.large)
                .disabled(model.isScanning)
            }
            Divider()
            HelpCard(module: .cleaner)

            if model.isScanning {
                ScanningView(text: "SweepIt fait le tour de votre Mac…")
            } else if !model.hasScanned {
                ContentUnavailableView {
                    Label("Prêt pour un coup de balai ?", systemImage: "sparkles")
                } description: {
                    Text("SweepIt va chercher les fichiers inutiles. Rien ne sera supprimé avant que vous ne validiez.")
                } actions: {
                    Button("Lancer l'analyse") { model.scan() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            } else if model.categories.isEmpty {
                ContentUnavailableView("Tout est propre !", systemImage: "checkmark.seal",
                                       description: Text("Il n'y a rien à nettoyer pour le moment."))
            } else {
                List {
                    ForEach(model.categories) { cat in
                        DisclosureGroup {
                            ForEach(cat.items) { item in
                                HStack {
                                    Toggle(isOn: model.binding(item.url)) { Text(item.name) }
                                        .toggleStyle(.checkbox)
                                    Spacer()
                                    Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .contextMenu {
                                    Button("Afficher dans le Finder") { FS.reveal([item.url]) }
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Button { model.toggle(cat) } label: {
                                    Image(systemName: model.state(cat).symbol).foregroundStyle(.tint)
                                }
                                .buttonStyle(.plain)
                                Image(systemName: cat.icon).foregroundStyle(.secondary).frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(cat.title).font(.headline)
                                    Text(cat.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                InfoButton(title: cat.title, text: cat.info)
                                RiskBadge(level: .safe)
                                Text(Fmt.bytes(cat.total)).monospacedDigit().bold().frame(minWidth: 70, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                TrashBar(count: model.selected.count, size: model.selectedSize, label: "Nettoyer") {
                    model.clean()
                }
            }
        }
        .trashReportAlert($model.report)
    }
}
