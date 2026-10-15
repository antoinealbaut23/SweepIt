import SwiftUI

struct DiskNode: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let isFolder: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum DiskMapScanner {
    private static let skipped: Set<String> = ["/System", "/private", "/dev", "/Volumes", "/cores"]

    /// Un niveau : chaque enfant avec sa taille récursive.
    static func level(_ url: URL, token: CancelToken, progress: (Double) -> Void) -> [DiskNode] {
        let kids = (try? FS.fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey])) ?? []
        var out: [DiskNode] = []
        for (i, k) in kids.enumerated() {
            if token.cancelled { break }
            if skipped.contains(k.path) { continue }
            let v = try? k.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let folder = v?.isDirectory == true && v?.isPackage != true
            let size = FS.allocatedSize(k, token: token)
            if size > 0 { out.append(DiskNode(url: k, size: size, isFolder: folder)) }
            progress(Double(i + 1) / Double(max(kids.count, 1)))
        }
        return out.sorted { $0.size > $1.size }
    }
}

enum Treemap {
    /// Algorithme « squarified » (Bruls et al.) : valeurs triées par ordre décroissant.
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 1, rect.height > 1 else { return values.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }
        var result: [CGRect] = []
        var remaining = rect
        var i = 0
        while i < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var row = [areas[i]]
            var j = i + 1
            while j < areas.count, worst(row + [areas[j]], side) <= worst(row, side) {
                row.append(areas[j])
                j += 1
            }
            let sum = row.reduce(0, +)
            if remaining.width >= remaining.height {
                let w = remaining.height > 0 ? CGFloat(sum / Double(remaining.height)) : 0
                var y = remaining.minY
                for a in row {
                    let h = w > 0 ? CGFloat(a) / w : 0
                    result.append(CGRect(x: remaining.minX, y: y, width: w, height: h))
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY,
                                   width: max(remaining.width - w, 0), height: remaining.height)
            } else {
                let h = remaining.width > 0 ? CGFloat(sum / Double(remaining.width)) : 0
                var x = remaining.minX
                for a in row {
                    let w = h > 0 ? CGFloat(a) / h : 0
                    result.append(CGRect(x: x, y: remaining.minY, width: w, height: h))
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h,
                                   width: remaining.width, height: max(remaining.height - h, 0))
            }
            i = j
        }
        return result
    }

    private static func worst(_ row: [Double], _ side: Double) -> Double {
        let s = row.reduce(0, +)
        guard let mx = row.max(), let mn = row.min(), mn > 0, s > 0, side > 0 else { return .infinity }
        return max(side * side * mx / (s * s), (s * s) / (side * side * mn))
    }
}

@Observable @MainActor
final class DiskMapModel {
    var stack: [URL] = []
    var nodes: [DiskNode] = []
    var isLoading = false
    var progress: Double = 0
    var hovered: DiskNode?
    var report: TrashReport?
    private var cache: [URL: [DiskNode]] = [:]
    private var token = CancelToken()

    static let maxTiles = 80
    var shown: [DiskNode] { Array(nodes.prefix(Self.maxTiles)) }
    var total: Int64 { nodes.reduce(0) { $0 + $1.size } }

    func start(_ url: URL) {
        stack = [url]
        cache = [:]
        load(url)
    }

    func open(_ node: DiskNode) {
        guard node.isFolder else { return }
        stack.append(node.url)
        load(node.url)
    }

    func goTo(_ index: Int) {
        stack = Array(stack.prefix(index + 1))
        if let u = stack.last { load(u) }
    }

    func load(_ url: URL) {
        hovered = nil
        token.cancelled = true
        if let c = cache[url] {
            nodes = c
            isLoading = false
            return
        }
        let token = CancelToken()
        self.token = token
        isLoading = true
        progress = 0
        nodes = []
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                DiskMapScanner.level(url, token: token) { p in
                    Task { @MainActor in if !token.cancelled { self.progress = p } }
                }
            }.value
            guard !token.cancelled else { return }
            cache[url] = result
            nodes = result
            isLoading = false
        }
    }

    func trash(_ node: DiskNode) {
        report = Trash.move([(node.url, node.size)])
        // Les tailles des dossiers parents ne sont plus à jour.
        cache = [:]
        if let u = stack.last { load(u) }
    }
}

struct DiskMapView: View {
    @Bindable var model: DiskMapModel
    @State private var confirmTrash: DiskNode?

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Espace disque",
                         subtitle: "Plus un bloc est grand, plus il prend de place.",
                         icon: "square.grid.3x3.square") {
                Button { model.start(Safety.home) } label: { Label("Dossier personnel", systemImage: "house") }
                Button {
                    if let u = FS.pickFolder(start: model.stack.last) { model.start(u) }
                } label: { Label("Choisir…", systemImage: "folder") }
                    .controlSize(.large)
            }
            Divider()
            HelpCard(module: .diskMap)

            if model.stack.isEmpty {
                ContentUnavailableView {
                    Label("Où est passé mon espace ?", systemImage: "square.grid.3x3.square")
                } description: {
                    Text("Affichez la carte de votre dossier personnel pour le découvrir.")
                } actions: {
                    Button("Afficher la carte") { model.start(Safety.home) }
                        .glassButtonStyle(prominent: true).controlSize(.large)
                }
            } else {
                breadcrumb
                Divider()
                if model.isLoading {
                    VStack(spacing: 12) {
                        ProgressView(value: model.progress).frame(width: 260)
                        Text("Calcul des tailles…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.nodes.isEmpty {
                    ContentUnavailableView("Dossier vide ou inaccessible", systemImage: "folder")
                } else {
                    HStack(spacing: 0) {
                        treemap.padding(12)
                        Divider()
                        sideList.frame(width: 260)
                    }
                    footer
                }
            }
        }
        .trashReportAlert($model.report)
        .confirmationDialog("Mettre « \(confirmTrash?.name ?? "") » à la corbeille ?",
                            isPresented: Binding(get: { confirmTrash != nil }, set: { if !$0 { confirmTrash = nil } }),
                            presenting: confirmTrash) { node in
            Button("Mettre à la corbeille", role: .destructive) { model.trash(node) }
        } message: { node in
            Text(Fmt.bytes(node.size))
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.stack.enumerated()), id: \.offset) { i, url in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                    Button(i == 0 ? url.path.replacingOccurrences(of: Safety.home.path, with: "~") : url.lastPathComponent) {
                        model.goTo(i)
                    }
                    .buttonStyle(.link)
                    .disabled(i == model.stack.count - 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private var treemap: some View {
        GeometryReader { geo in
            let shown = model.shown
            let rects = Treemap.layout(shown.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, node in
                    let r = rects[i].insetBy(dx: 1.5, dy: 1.5)
                    if r.width > 0 && r.height > 0 {
                        tile(node, index: i, rect: r)
                    }
                }
            }
        }
    }

    private func tile(_ node: DiskNode, index: Int, rect r: CGRect) -> some View {
        let hue = (Double(index) * 0.618_034).truncatingRemainder(dividingBy: 1)
        let color = node.isFolder ? Color(hue: hue, saturation: 0.5, brightness: 0.8)
                                  : Color(hue: hue, saturation: 0.15, brightness: 0.6)
        return RoundedRectangle(cornerRadius: 5)
            .fill(color.gradient)
            .overlay(alignment: .topLeading) {
                if r.width > 70 && r.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name).font(.caption.bold()).lineLimit(1)
                        Text(Fmt.bytes(node.size)).font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .padding(6)
                }
            }
            .overlay {
                if model.hovered == node {
                    RoundedRectangle(cornerRadius: 5).stroke(.white, lineWidth: 2)
                }
            }
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
            .onHover { inside in
                if inside { model.hovered = node } else if model.hovered == node { model.hovered = nil }
            }
            .onTapGesture { model.open(node) }
            .contextMenu { menu(node) }
            .help("\(node.name) — \(Fmt.bytes(node.size))")
    }

    @ViewBuilder
    private func menu(_ node: DiskNode) -> some View {
        if node.isFolder { Button("Ouvrir") { model.open(node) } }
        Button("Afficher dans le Finder") { FS.reveal([node.url]) }
        if Safety.canTrash(node.url) {
            Divider()
            Button("Mettre à la corbeille…", role: .destructive) { confirmTrash = node }
        }
    }

    private var sideList: some View {
        List(model.nodes) { node in
            HStack(spacing: 8) {
                Image(nsImage: FS.icon(node.url)).resizable().frame(width: 18, height: 18)
                Text(node.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Fmt.bytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open(node) }
            .contextMenu { menu(node) }
        }
    }

    private var footer: some View {
        HStack {
            HStack {
                if let h = model.hovered {
                    Text(h.name).bold()
                    Text(Fmt.bytes(h.size))
                    if model.total > 0 {
                        Text(String(format: "%.1f %%", Double(h.size) / Double(model.total) * 100)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Total : \(Fmt.bytes(model.total)) · \(model.nodes.count) éléments")
                        .foregroundStyle(.secondary)
                    if model.nodes.count > DiskMapModel.maxTiles {
                        Text("(\(DiskMapModel.maxTiles) plus gros affichés)").foregroundStyle(.tertiary)
                    }
                }
            }
            .glassCapsule()
            Spacer()
        }
        .monospacedDigit()
        .glassBottomBar()
    }
}
