import CoreServices
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Catégories

enum DeskCategory: String, CaseIterable, Identifiable {
    case screenshots, images, videos, audio, documents, archives, installers, others

    var id: Self { self }

    var title: String {
        switch self {
        case .screenshots: "Captures d'écran"
        case .images: "Images"
        case .videos: "Vidéos"
        case .audio: "Audio"
        case .documents: "Documents"
        case .archives: "Archives"
        case .installers: "Installateurs"
        case .others: "Divers"
        }
    }

    var icon: String {
        switch self {
        case .screenshots: "camera.viewfinder"
        case .images: "photo"
        case .videos: "film"
        case .audio: "music.note"
        case .documents: "doc.text"
        case .archives: "archivebox"
        case .installers: "shippingbox"
        case .others: "questionmark.folder"
        }
    }

    var color: Color {
        switch self {
        case .screenshots: .purple
        case .images: .pink
        case .videos: .red
        case .audio: .orange
        case .documents: .blue
        case .archives: .brown
        case .installers: .teal
        case .others: .gray
        }
    }

    var explanation: String {
        switch self {
        case .screenshots: "Les images créées quand vous appuyez sur ⌘⇧3 ou ⌘⇧4, et les enregistrements d'écran. Elles s'accumulent très vite sur le Bureau !"
        case .images: "Photos et images (JPEG, PNG, HEIC…)."
        case .videos: "Films et vidéos."
        case .audio: "Musique, mémos vocaux et sons."
        case .documents: "PDF, textes, tableurs et présentations (Word, Pages, Excel, Keynote…)."
        case .archives: "Fichiers compressés (.zip, .rar…). Une fois ouverts, l'archive d'origine ne sert souvent plus."
        case .installers: "Fichiers d'installation d'apps (.dmg, .pkg). Une fois l'app installée, ils ne servent plus : la corbeille est souvent le bon choix."
        case .others: "Tout ce qui ne rentre dans aucune autre catégorie."
        }
    }

    /// Conseil affiché à côté de la catégorie, s'il y en a un.
    var suggestion: String? {
        switch self {
        case .installers: "Conseil : la corbeille"
        case .archives: "Souvent inutiles une fois ouvertes"
        default: nil
        }
    }

    func destination(_ mode: DestinationMode) -> URL {
        let h = Safety.home
        switch mode {
        case .desktop:
            return h.appendingPathComponent("Desktop/\(title)")
        case .home:
            switch self {
            case .screenshots: return h.appendingPathComponent("Pictures/Captures d'écran")
            case .images: return h.appendingPathComponent("Pictures")
            case .videos: return h.appendingPathComponent("Movies")
            case .audio: return h.appendingPathComponent("Music")
            case .documents: return h.appendingPathComponent("Documents")
            case .archives: return h.appendingPathComponent("Downloads/Archives")
            case .installers: return h.appendingPathComponent("Downloads/Installateurs")
            case .others: return h.appendingPathComponent("Documents/Divers")
            }
        }
    }

    /// Chemin lisible, avec les noms français des dossiers du Finder.
    func destinationLabel(_ mode: DestinationMode) -> String {
        destination(mode).path
            .replacingOccurrences(of: Safety.home.path + "/", with: "")
            .replacingOccurrences(of: "Desktop", with: "Bureau")
            .replacingOccurrences(of: "Pictures", with: "Images")
            .replacingOccurrences(of: "Movies", with: "Vidéos")
            .replacingOccurrences(of: "Music", with: "Musique")
            .replacingOccurrences(of: "Downloads", with: "Téléchargements")
            .replacingOccurrences(of: "/", with: " › ")
    }
}

enum DestinationMode: String, CaseIterable, Identifiable {
    case desktop = "Dans des dossiers sur le Bureau"
    case home = "Dans vos dossiers (Images, Documents…)"
    var id: Self { self }
}

enum DeskAction: String, CaseIterable, Identifiable {
    case organize = "Ranger"
    case trash = "Corbeille"
    case keep = "Laisser"
    var id: Self { self }
}

struct DeskItem: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date?
    let category: DeskCategory
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum DeskScanner {
    static let desktop = Safety.home.appendingPathComponent("Desktop")

    private static let screenshotPrefixes = ["Capture d’écran", "Capture d'écran", "Screenshot", "Screen Shot",
                                             "Enregistrement de l’écran", "Enregistrement de l'écran", "Screen Recording"]
    private static let documentExtensions: Set<String> = ["doc", "docx", "pages", "rtf", "odt", "numbers", "key",
                                                          "xls", "xlsx", "ppt", "pptx", "epub", "csv", "md", "txt"]
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
    private static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]

    static func scan() -> [DeskItem] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        let files = (try? FS.fm.contentsOfDirectory(at: desktop, includingPropertiesForKeys: Array(keys),
                                                    options: [.skipsHiddenFiles])) ?? []
        return files.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { return nil }
            return DeskItem(url: url, size: Int64(v.totalFileAllocatedSize ?? 0),
                            modified: v.contentModificationDate, category: classify(url))
        }
        .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    static func classify(_ url: URL) -> DeskCategory {
        if isScreenshot(url) { return .screenshots }
        let ext = url.pathExtension.lowercased()
        if installerExtensions.contains(ext) { return .installers }
        if archiveExtensions.contains(ext) { return .archives }
        if documentExtensions.contains(ext) { return .documents }
        guard let t = UTType(filenameExtension: ext) else { return .others }
        if t.conforms(to: .image) { return .images }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .videos }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .diskImage) { return .installers }
        if t.conforms(to: .archive) { return .archives }
        if t.conforms(to: .pdf) || t.conforms(to: .text) || t.conforms(to: .presentation)
            || t.conforms(to: .spreadsheet) { return .documents }
        return .others
    }

    private static func isScreenshot(_ url: URL) -> Bool {
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool, flag {
            return true
        }
        let name = url.lastPathComponent
        return screenshotPrefixes.contains { name.hasPrefix($0) }
    }

    /// « photo.png » → « photo 2.png » si le nom est déjà pris.
    static func uniqueURL(_ url: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var candidate = url
        var i = 2
        while FS.exists(candidate) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            i += 1
        }
        return candidate
    }
}

// MARK: - Modèle

struct OrganizeResult {
    var moved = 0
    var trashed = 0
    var failures: [String] = []

    var message: String {
        var parts: [String] = []
        if moved > 0 { parts.append("\(moved) fichier\(moved > 1 ? "s" : "") rangé\(moved > 1 ? "s" : "")") }
        if trashed > 0 { parts.append("\(trashed) mis à la corbeille") }
        var msg = parts.isEmpty ? "Aucun fichier déplacé." : parts.joined(separator: ", ") + "."
        if !failures.isEmpty {
            msg += "\n\n\(failures.count) échec\(failures.count > 1 ? "s" : "") :\n" + failures.prefix(5).joined(separator: "\n")
        }
        return msg
    }
}

@Observable @MainActor
final class DesktopModel {
    var items: [DeskItem] = []
    var selected: Set<URL> = []
    var actions: [DeskCategory: DeskAction] = [:]
    var mode: DestinationMode = .desktop
    var isScanning = false
    var hasScanned = false
    var result: OrganizeResult?
    /// Déplacements du dernier rangement, pour pouvoir l'annuler.
    private(set) var undoLog: [(original: URL, now: URL)] = []

    var categories: [DeskCategory] { DeskCategory.allCases.filter { c in items.contains { $0.category == c } } }
    var canUndo: Bool { !undoLog.isEmpty }

    func items(in c: DeskCategory) -> [DeskItem] { items.filter { $0.category == c } }
    func action(for c: DeskCategory) -> DeskAction { actions[c] ?? .organize }

    func count(_ action: DeskAction) -> Int {
        items.filter { selected.contains($0.url) && self.action(for: $0.category) == action }.count
    }

    func scan() {
        isScanning = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { DeskScanner.scan() }.value
            items = found
            selected = Set(found.map(\.url))
            isScanning = false
            hasScanned = true
        }
    }

    func actionBinding(_ c: DeskCategory) -> Binding<DeskAction> {
        Binding(get: { self.action(for: c) }, set: { self.actions[c] = $0 })
    }

    func binding(_ url: URL) -> Binding<Bool> {
        Binding(get: { self.selected.contains(url) },
                set: { if $0 { self.selected.insert(url) } else { self.selected.remove(url) } })
    }

    func apply() {
        var r = OrganizeResult()
        var log: [(URL, URL)] = []
        let desktop = DeskScanner.desktop.standardizedFileURL.path + "/"
        for item in items where selected.contains(item.url) {
            guard item.url.standardizedFileURL.path.hasPrefix(desktop) else { continue }
            do {
                switch action(for: item.category) {
                case .keep:
                    continue
                case .organize:
                    let dir = item.category.destination(mode)
                    try FS.fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    let target = DeskScanner.uniqueURL(dir.appendingPathComponent(item.name))
                    try FS.fm.moveItem(at: item.url, to: target)
                    log.append((item.url, target))
                    r.moved += 1
                case .trash:
                    var inTrash: NSURL?
                    try FS.fm.trashItem(at: item.url, resultingItemURL: &inTrash)
                    if let t = inTrash as URL? { log.append((item.url, t)) }
                    r.trashed += 1
                }
            } catch {
                r.failures.append("\(item.name) : \(error.localizedDescription)")
            }
        }
        undoLog = log
        result = r
        scan()
    }

    /// Remet chaque fichier du dernier rangement à sa place d'origine (y compris depuis la corbeille).
    func undo() {
        var failures: [String] = []
        for (original, now) in undoLog.reversed() {
            guard FS.exists(now) else { continue }
            do { try FS.fm.moveItem(at: now, to: DeskScanner.uniqueURL(original)) }
            catch { failures.append("\(original.lastPathComponent) : \(error.localizedDescription)") }
        }
        undoLog = []
        if !failures.isEmpty { result = OrganizeResult(failures: failures) }
        scan()
    }
}

// MARK: - Vue

struct DesktopView: View {
    @Bindable var model: DesktopModel
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Organiseur de bureau",
                         subtitle: "Rangez votre Bureau en un clic.",
                         icon: "menubar.dock.rectangle") {
                if model.canUndo {
                    Button { model.undo() } label: {
                        Label("Annuler le rangement", systemImage: "arrow.uturn.backward")
                    }
                }
                Button { model.scan() } label: {
                    Label(model.hasScanned ? "Réanalyser" : "Analyser", systemImage: "magnifyingglass")
                }
                .controlSize(.large)
                .disabled(model.isScanning)
            }
            Divider()
            HelpCard(module: .desktop)

            if model.isScanning {
                ScanningView(text: "SweepIt regarde votre Bureau…")
            } else if !model.hasScanned {
                ContentUnavailableView {
                    Label("Un Bureau en désordre ?", systemImage: "menubar.dock.rectangle")
                } description: {
                    Text("SweepIt va trier vos fichiers par type. Vous choisirez ensuite quoi ranger, garder ou jeter.")
                } actions: {
                    Button("Analyser mon Bureau") { model.scan() }
                        .glassButtonStyle(prominent: true).controlSize(.large)
                }
            } else if model.items.isEmpty {
                ContentUnavailableView("Votre Bureau est déjà rangé !", systemImage: "checkmark.seal",
                                       description: Text("Aucun fichier à trier pour le moment."))
            } else {
                HStack {
                    Text("Où ranger les fichiers ?").bold()
                    Picker("", selection: $model.mode) {
                        ForEach(DestinationMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                Divider()

                ScrollView {
                    GlassGroup {
                        LazyVStack(spacing: 12) {
                            ForEach(model.categories) { CategoryCard(model: model, category: $0) }
                        }
                    }
                    .padding(20)
                }
                bottomBar
            }
        }
        .alert("Bureau rangé", isPresented: Binding(get: { model.result != nil }, set: { if !$0 { model.result = nil } }),
               presenting: model.result) { _ in
            Button("OK") {}
            if model.canUndo { Button("Annuler le rangement") { model.undo() } }
        } message: { r in
            Text(r.message)
        }
    }

    private var bottomBar: some View {
        let toMove = model.count(.organize), toTrash = model.count(.trash)
        return GlassGroup {
            HStack {
                Text(summary(toMove, toTrash)).foregroundStyle(.secondary)
                    .glassCapsule()
                Spacer()
                Button { confirm = true } label: { Label("Ranger mon Bureau", systemImage: "sparkles") }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)
                    .disabled(toMove + toTrash == 0)
            }
        }
        .glassBottomBar()
        .confirmationDialog("Ranger votre Bureau ?", isPresented: $confirm) {
            Button("Ranger") { model.apply() }
        } message: {
            Text(summary(toMove, toTrash) + ". Vous pourrez tout annuler ensuite.")
        }
    }

    private func summary(_ move: Int, _ trash: Int) -> String {
        var parts: [String] = []
        if move > 0 { parts.append("\(move) à ranger") }
        if trash > 0 { parts.append("\(trash) à mettre à la corbeille") }
        return parts.isEmpty ? "Rien de sélectionné" : parts.joined(separator: " · ")
    }
}

private struct CategoryCard: View {
    @Bindable var model: DesktopModel
    let category: DeskCategory
    @State private var expanded = false

    var body: some View {
        let files = model.items(in: category)
        let action = model.action(for: category)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(category.color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(category.title).font(.headline)
                        InfoButton(title: category.title, text: category.explanation)
                    }
                    Text("\(files.count) fichier\(files.count > 1 ? "s" : "") · \(Fmt.bytes(files.reduce(0) { $0 + $1.size }))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let s = category.suggestion {
                    Text(s).font(.caption).foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
                Picker("", selection: model.actionBinding(category)) {
                    ForEach(DeskAction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)
            }

            HStack(spacing: 6) {
                switch action {
                case .organize:
                    Image(systemName: "arrow.turn.down.right")
                    Text("Seront rangés dans ") + Text(category.destinationLabel(model.mode)).bold()
                case .trash:
                    Image(systemName: "trash")
                    Text("Iront à la corbeille (récupérables tant qu'elle n'est pas vidée)")
                case .keep:
                    Image(systemName: "pin")
                    Text("Resteront sur le Bureau")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 4) {
                    ForEach(files) { f in
                        HStack(spacing: 8) {
                            Toggle(isOn: model.binding(f.url)) { EmptyView() }.toggleStyle(.checkbox)
                            Image(nsImage: FS.icon(f.url)).resizable().frame(width: 18, height: 18)
                            Text(f.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.date(f.modified)).foregroundStyle(.secondary)
                            Text(Fmt.bytes(f.size)).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .contextMenu {
                            Button("Ouvrir") { NSWorkspace.shared.open(f.url) }
                            Button("Afficher dans le Finder") { FS.reveal([f.url]) }
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(expanded ? "Masquer les fichiers" : "Voir les fichiers").font(.callout)
            }
        }
        .padding(14)
        .glassCard()
        .opacity(action == .keep ? 0.6 : 1)
    }
}
