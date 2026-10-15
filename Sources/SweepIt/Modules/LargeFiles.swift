import SwiftUI

enum AgeFilter: String, CaseIterable, Identifiable {
    case any = "Toutes dates"
    case sixMonths = "Plus de 6 mois"
    case oneYear = "Plus d'un an"
    case twoYears = "Plus de 2 ans"

    var id: Self { self }
    var cutoff: Date? {
        let cal = Calendar.current
        switch self {
        case .any: return nil
        case .sixMonths: return cal.date(byAdding: .month, value: -6, to: .now)
        case .oneYear: return cal.date(byAdding: .year, value: -1, to: .now)
        case .twoYears: return cal.date(byAdding: .year, value: -2, to: .now)
        }
    }
}

enum LargeFileScanner {
    static func scan(root: URL, minBytes: Int64, cutoff: Date?, token: CancelToken,
                     progress: (Int) -> Void) -> [FileEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .contentModificationDateKey]
        let keySet = Set(keys)
        guard let e = FS.fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                       errorHandler: { _, _ in true }) else { return [] }
        var out: [FileEntry] = []
        var n = 0
        for case let url as URL in e {
            if token.cancelled { break }
            n += 1
            if n % 2000 == 0 { progress(n) }
            if Safety.scanExclusions.contains(url.path) { e.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: keySet),
                  v.isRegularFile == true, v.isPackage != true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            guard size >= minBytes else { continue }
            if let c = cutoff, let m = v.contentModificationDate, m > c { continue }
            out.append(FileEntry(url: url, size: size, modified: v.contentModificationDate))
        }
        return out.sorted { $0.size > $1.size }
    }
}

@Observable @MainActor
final class LargeFilesModel {
    var root: URL = Safety.home
    var minMB = 100
    var age: AgeFilter = .any
    var results: [FileEntry] = []
    var selection: Set<URL> = []
    var sortOrder = [KeyPathComparator(\FileEntry.size, order: .reverse)]
    var isScanning = false
    var hasScanned = false
    var scanned = 0
    var report: TrashReport?
    private var token = CancelToken()

    var selectedItems: [FileEntry] { results.filter { selection.contains($0.url) } }

    func scan() {
        token.cancelled = true
        let token = CancelToken()
        self.token = token
        isScanning = true
        scanned = 0
        selection = []
        let root = root, minBytes = Int64(minMB) * 1_000_000, cutoff = age.cutoff
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                LargeFileScanner.scan(root: root, minBytes: minBytes, cutoff: cutoff, token: token) { n in
                    Task { @MainActor in self.scanned = n }
                }
            }.value
            guard !token.cancelled else { return }
            results = found.sorted(using: sortOrder)
            isScanning = false
            hasScanned = true
        }
    }

    func cancel() {
        token.cancelled = true
        isScanning = false
    }

    func trashSelection() {
        let items = selectedItems
        report = Trash.move(items.map { ($0.url, $0.size) })
        let gone = Set(items.map(\.url).filter { !FS.exists($0) })
        results.removeAll { gone.contains($0.url) }
        selection.subtract(gone)
    }
}

struct LargeFilesView: View {
    @Bindable var model: LargeFilesModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Gros et vieux fichiers",
                         subtitle: "Retrouvez ce qui prend de la place et que vous n'ouvrez plus.",
                         icon: "doc.badge.ellipsis") {
                FolderPickerButton(url: $model.root)
                Picker("", selection: $model.minMB) {
                    ForEach([50, 100, 500, 1000, 5000], id: \.self) { mb in
                        Text(mb >= 1000 ? "> \(mb / 1000) Go" : "> \(mb) Mo").tag(mb)
                    }
                }
                .frame(width: 100)
                Picker("", selection: $model.age) {
                    ForEach(AgeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 140)
                Button { model.scan() } label: { Label("Analyser", systemImage: "magnifyingglass") }
                    .controlSize(.large)
                    .disabled(model.isScanning)
            }
            Divider()
            HelpCard(module: .largeFiles)

            if model.isScanning {
                ScanningView(text: "\(model.scanned) fichiers examinés…") { model.cancel() }
            } else if !model.hasScanned {
                ContentUnavailableView("Choisissez un dossier et lancez l'analyse", systemImage: "doc.badge.ellipsis",
                                       description: Text("Par sécurité, les dossiers système, les apps et la photothèque sont ignorés."))
            } else if model.results.isEmpty {
                ContentUnavailableView("Aucun gros fichier trouvé", systemImage: "checkmark.seal",
                                       description: Text("Essayez une taille plus petite ou un autre dossier."))
            } else {
                Table(model.results, selection: $model.selection, sortOrder: $model.sortOrder) {
                    TableColumn("Nom", value: \.name) { e in
                        HStack(spacing: 6) {
                            Image(nsImage: FS.icon(e.url)).resizable().frame(width: 16, height: 16)
                            Text(e.name).lineLimit(1)
                        }
                    }
                    .width(min: 180, ideal: 260)
                    TableColumn("Taille", value: \.size) { e in
                        Text(Fmt.bytes(e.size)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Modifié", value: \.modifiedSort) { e in
                        Text(Fmt.date(e.modified)).foregroundStyle(.secondary)
                    }
                    .width(110)
                    TableColumn("Emplacement", value: \.folder) { e in
                        Text(e.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .contextMenu(forSelectionType: URL.self) { urls in
                    Button("Afficher dans le Finder") { FS.reveal(Array(urls)) }
                } primaryAction: { urls in
                    FS.reveal(Array(urls))
                }
                .onChange(of: model.sortOrder) { _, order in model.results.sort(using: order) }

                TrashBar(count: model.selection.count,
                         size: model.selectedItems.reduce(0) { $0 + $1.size }) {
                    model.trashSelection()
                }
            }
        }
        .trashReportAlert($model.report)
    }
}
