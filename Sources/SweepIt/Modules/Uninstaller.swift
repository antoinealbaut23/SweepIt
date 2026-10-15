import SwiftUI

struct AppInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    var id: URL { url }
}

struct Leftover: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let kind: String
    var id: URL { url }
}

enum AppScanner {
    static func installedApps() -> [AppInfo] {
        let dirs = [URL(fileURLWithPath: "/Applications"), Safety.home.appendingPathComponent("Applications")]
        var out: [AppInfo] = []
        for dir in dirs {
            for url in FS.children(dir) where url.pathExtension == "app" {
                guard let b = Bundle(url: url), let id = b.bundleIdentifier,
                      !id.hasPrefix("com.apple.") else { continue }
                let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                out.append(AppInfo(url: url, name: name, bundleID: id, version: version))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static let libraryFolders: [(String, String)] = [
        ("Application Support", "Données"),
        ("Caches", "Cache"),
        ("Preferences", "Préférences"),
        ("Preferences/ByHost", "Préférences"),
        ("Containers", "Conteneur"),
        ("Group Containers", "Conteneur partagé"),
        ("Saved Application State", "État de fenêtre"),
        ("Logs", "Journaux"),
        ("HTTPStorages", "Stockage web"),
        ("WebKit", "Stockage web"),
        ("Cookies", "Cookies"),
        ("LaunchAgents", "Agent de démarrage"),
        ("Application Scripts", "Scripts"),
    ]

    /// Fichiers laissés par l'app dans ~/Library, retrouvés par identifiant ou par nom exact.
    static func leftovers(for app: AppInfo) -> [Leftover] {
        let bid = app.bundleID.lowercased()
        let appName = app.name.lowercased()
        let fileName = app.url.deletingPathExtension().lastPathComponent.lowercased()
        var out = [Leftover(url: app.url, size: FS.allocatedSize(app.url), kind: "Application")]
        var seen: Set<URL> = [app.url]
        for (folder, kind) in libraryFolders {
            let dir = Safety.home.appendingPathComponent("Library/" + folder)
            for item in FS.children(dir) {
                let n = item.lastPathComponent.lowercased()
                let matches = n == bid || n.hasPrefix(bid + ".") || n.hasSuffix("." + bid)
                    || n == appName || n == fileName
                guard matches, !seen.contains(item), Safety.canTrash(item) else { continue }
                seen.insert(item)
                out.append(Leftover(url: item, size: FS.allocatedSize(item), kind: kind))
            }
        }
        return out
    }
}

@Observable @MainActor
final class UninstallerModel {
    var apps: [AppInfo] = []
    var search = ""
    var selectedApp: AppInfo.ID?
    var leftovers: [Leftover] = []
    var selected: Set<URL> = []
    var isLoadingApps = false
    var isLoadingLeftovers = false
    var report: TrashReport?
    var errorMessage: String?

    var filtered: [AppInfo] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var current: AppInfo? { apps.first { $0.id == selectedApp } }
    var selectedSize: Int64 { leftovers.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size } }

    func loadApps() {
        isLoadingApps = true
        Task {
            apps = await Task.detached { AppScanner.installedApps() }.value
            isLoadingApps = false
        }
    }

    func select(_ id: AppInfo.ID?) {
        leftovers = []
        selected = []
        guard let app = apps.first(where: { $0.id == id }) else { return }
        isLoadingLeftovers = true
        Task {
            let found = await Task.detached { AppScanner.leftovers(for: app) }.value
            guard selectedApp == app.id else { return }
            leftovers = found
            selected = Set(found.map(\.url))
            isLoadingLeftovers = false
        }
    }

    func uninstall() {
        guard let app = current else { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty {
            errorMessage = "Quittez « \(app.name) » avant de la désinstaller."
            return
        }
        let items = leftovers.filter { selected.contains($0.url) }
        report = Trash.move(items.map { ($0.url, $0.size) })
        if !FS.exists(app.url) {
            apps.removeAll { $0.id == app.id }
            selectedApp = nil
            leftovers = []
            selected = []
        } else {
            select(app.id)
        }
    }

    func binding(_ url: URL) -> Binding<Bool> {
        Binding(get: { self.selected.contains(url) },
                set: { if $0 { self.selected.insert(url) } else { self.selected.remove(url) } })
    }
}

struct UninstallerView: View {
    @Bindable var model: UninstallerModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Désinstallateur",
                         subtitle: "Retirez une app et tout ce qu'elle a laissé derrière elle.",
                         icon: "xmark.app") {
                Button { model.loadApps() } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
            }
            Divider()
            HelpCard(module: .uninstaller)
            HStack(spacing: 0) {
                appList.frame(width: 280)
                Divider()
                detail.frame(maxWidth: .infinity)
            }
        }
        .onAppear { if model.apps.isEmpty { model.loadApps() } }
        .onChange(of: model.selectedApp) { _, id in model.select(id) }
        .trashReportAlert($model.report)
        .alert("Impossible de désinstaller",
               isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            TextField("Rechercher", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            if model.isLoadingApps {
                ProgressView().frame(maxHeight: .infinity)
            } else {
                List(model.filtered, selection: $model.selectedApp) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: FS.icon(app.url)).resizable().frame(width: 24, height: 24)
                        Text(app.name).lineLimit(1)
                    }
                    .tag(app.id)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.current {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(nsImage: FS.icon(app.url)).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title3.bold())
                        Text([app.version, app.bundleID].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                Divider()
                if model.isLoadingLeftovers {
                    ScanningView(text: "Recherche des fichiers laissés par l'app…")
                } else {
                    List(model.leftovers) { item in
                        HStack(spacing: 8) {
                            Toggle(isOn: model.binding(item.url)) { EmptyView() }.toggleStyle(.checkbox)
                            Image(nsImage: FS.icon(item.url)).resizable().frame(width: 18, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.url.lastPathComponent).lineLimit(1)
                                Text(item.url.deletingLastPathComponent().path
                                        .replacingOccurrences(of: Safety.home.path, with: "~"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(item.kind).font(.caption).foregroundStyle(.secondary)
                            Text(Fmt.bytes(item.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                        .contextMenu { Button("Afficher dans le Finder") { FS.reveal([item.url]) } }
                    }
                    TrashBar(count: model.selected.count, size: model.selectedSize, label: "Désinstaller") {
                        model.uninstall()
                    }
                }
            }
        } else {
            ContentUnavailableView("Sélectionnez une application", systemImage: "xmark.app",
                                   description: Text("Choisissez une app dans la liste de gauche. Les apps d'Apple (Safari, Mail…) sont protégées et n'apparaissent pas."))
        }
    }
}
