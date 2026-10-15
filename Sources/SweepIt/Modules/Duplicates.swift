import CryptoKit
import SwiftUI

struct DupGroup: Identifiable {
    let id: String
    let size: Int64
    var files: [FileEntry]
    var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
}

enum DuplicateScanner {
    /// Taille identique → empreinte des 64 premiers Ko → empreinte complète.
    static func scan(root: URL, minBytes: Int64, token: CancelToken,
                     progress: (String) -> Void) -> [DupGroup] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .fileSizeKey,
                                      .contentModificationDateKey, .fileResourceIdentifierKey]
        let keySet = Set(keys)
        guard let e = FS.fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                       errorHandler: { _, _ in true }) else { return [] }

        var bySize: [Int64: [FileEntry]] = [:]
        var seenInodes = Set<NSObject>()
        var n = 0
        for case let url as URL in e {
            if token.cancelled { return [] }
            n += 1
            if n % 2000 == 0 { progress("\(n) fichiers parcourus…") }
            if Safety.scanExclusions.contains(url.path) { e.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: keySet),
                  v.isRegularFile == true, v.isPackage != true,
                  let size = v.fileSize.map(Int64.init), size >= max(minBytes, 1) else { continue }
            // Les liens physiques pointent vers le même fichier : pas un doublon.
            if let ident = v.fileResourceIdentifier as? NSObject {
                if seenInodes.contains(ident) { continue }
                seenInodes.insert(ident)
            }
            bySize[size, default: []].append(FileEntry(url: url, size: size, modified: v.contentModificationDate))
        }

        let candidates = bySize.values.filter { $0.count > 1 }
        let total = candidates.reduce(0) { $0 + $1.count }
        var done = 0
        var groups: [DupGroup] = []

        for sameSize in candidates {
            if token.cancelled { return [] }
            var byPartial: [String: [FileEntry]] = [:]
            for f in sameSize {
                done += 1
                if done % 50 == 0 { progress("Comparaison : \(done) / \(total) fichiers…") }
                if let h = hash(f.url, limit: 64 * 1024) { byPartial[h, default: []].append(f) }
            }
            for partial in byPartial.values where partial.count > 1 {
                var byFull: [String: [FileEntry]] = [:]
                for f in partial {
                    if token.cancelled { return [] }
                    if let h = hash(f.url, limit: nil) { byFull[h, default: []].append(f) }
                }
                for (h, files) in byFull where files.count > 1 {
                    groups.append(DupGroup(id: h, size: files[0].size,
                                           files: files.sorted { $0.modifiedSort < $1.modifiedSort }))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var read = 0
        let chunk = 1 << 20
        while true {
            let want = limit.map { min(chunk, $0 - read) } ?? chunk
            if want <= 0 { break }
            let data: Data? = autoreleasepool { try? h.read(upToCount: want) }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
            read += data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@Observable @MainActor
final class DuplicatesModel {
    var root: URL = Safety.home
    var minMB = 1
    var groups: [DupGroup] = []
    var selected: Set<URL> = []
    var isScanning = false
    var hasScanned = false
    var status = ""
    var report: TrashReport?
    private var token = CancelToken()

    var selectedItems: [FileEntry] { groups.flatMap(\.files).filter { selected.contains($0.url) } }

    func scan() {
        token.cancelled = true
        let token = CancelToken()
        self.token = token
        isScanning = true
        status = "Recherche…"
        let root = root, minBytes = Int64(minMB) * 1_000_000
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                DuplicateScanner.scan(root: root, minBytes: minBytes, token: token) { s in
                    Task { @MainActor in if !token.cancelled { self.status = s } }
                }
            }.value
            guard !token.cancelled else { return }
            groups = found
            // Par défaut on garde le plus ancien de chaque groupe.
            selected = Set(found.flatMap { $0.files.dropFirst().map(\.url) })
            isScanning = false
            hasScanned = true
        }
    }

    func cancel() {
        token.cancelled = true
        isScanning = false
    }

    func binding(_ url: URL) -> Binding<Bool> {
        Binding(get: { self.selected.contains(url) },
                set: { if $0 { self.selected.insert(url) } else { self.selected.remove(url) } })
    }

    func trashSelection() {
        // Garde-fou : on ne supprime jamais toutes les copies d'un groupe.
        var toTrash: [FileEntry] = []
        for g in groups {
            let picked = g.files.filter { selected.contains($0.url) }
            toTrash += picked.count == g.files.count ? Array(picked.dropFirst()) : picked
        }
        report = Trash.move(toTrash.map { ($0.url, $0.size) })
        let gone = Set(toTrash.map(\.url).filter { !FS.exists($0) })
        selected.subtract(gone)
        groups = groups.compactMap { g in
            var g = g
            g.files.removeAll { gone.contains($0.url) }
            return g.files.count > 1 ? g : nil
        }
    }
}

struct DuplicatesView: View {
    @Bindable var model: DuplicatesModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Doublons",
                         subtitle: "Retrouvez les fichiers présents en double sur votre Mac.",
                         icon: "doc.on.doc") {
                FolderPickerButton(url: $model.root)
                Picker("", selection: $model.minMB) {
                    ForEach([0, 1, 10, 100], id: \.self) { mb in
                        Text(mb == 0 ? "Toutes tailles" : "> \(mb) Mo").tag(mb)
                    }
                }
                .frame(width: 120)
                Button { model.scan() } label: { Label("Analyser", systemImage: "magnifyingglass") }
                    .controlSize(.large)
                    .disabled(model.isScanning)
            }
            Divider()
            HelpCard(module: .duplicates)

            if model.isScanning {
                ScanningView(text: model.status) { model.cancel() }
            } else if !model.hasScanned {
                ContentUnavailableView("Choisissez un dossier et lancez l'analyse", systemImage: "doc.on.doc",
                                       description: Text("Le plus ancien fichier de chaque groupe est conservé par défaut."))
            } else if model.groups.isEmpty {
                ContentUnavailableView("Aucun doublon trouvé", systemImage: "checkmark.seal")
            } else {
                List {
                    ForEach(model.groups) { g in
                        Section {
                            ForEach(g.files) { f in
                                HStack(spacing: 8) {
                                    Toggle(isOn: model.binding(f.url)) { EmptyView() }
                                        .toggleStyle(.checkbox)
                                    Image(nsImage: FS.icon(f.url)).resizable().frame(width: 18, height: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(f.name).lineLimit(1)
                                        Text(f.folder).font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text(Fmt.date(f.modified)).foregroundStyle(.secondary)
                                }
                                .contextMenu { Button("Afficher dans le Finder") { FS.reveal([f.url]) } }
                            }
                        } header: {
                            HStack {
                                Text("\(g.files.count) copies · \(Fmt.bytes(g.size)) chacune")
                                Spacer()
                                Text("\(Fmt.bytes(g.wasted)) à gagner").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                TrashBar(count: model.selected.count,
                         size: model.selectedItems.reduce(0) { $0 + $1.size }) {
                    model.trashSelection()
                }
            }
        }
        .trashReportAlert($model.report)
    }
}
