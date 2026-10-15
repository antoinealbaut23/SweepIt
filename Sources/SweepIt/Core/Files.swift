import AppKit
import Foundation

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let size: Int64
    var modified: Date? = nil

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var modifiedSort: Date { modified ?? .distantPast }
    var folder: String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: Safety.home.path, with: "~")
    }
}

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func date(_ d: Date?) -> String {
        d.map { dateFormatter.string(from: $0) } ?? "—"
    }
}

/// Drapeau d'annulation partagé avec les scans qui tournent hors du main thread.
final class CancelToken: @unchecked Sendable {
    var cancelled = false
}

enum FS {
    static let fm = FileManager.default

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func children(_ url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    }

    /// Taille réellement occupée sur le disque, récursive pour les dossiers.
    static func allocatedSize(_ url: URL, token: CancelToken? = nil) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey,
                                         .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                    options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if token?.cancelled == true { break }
            guard let fv = try? f.resourceValues(forKeys: keys), fv.isRegularFile == true else { continue }
            total += Int64(fv.totalFileAllocatedSize ?? fv.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func icon(_ url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    @MainActor
    static func pickFolder(start: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
        panel.prompt = "Choisir"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct TrashReport {
    var moved = 0
    var freed: Int64 = 0
    var failures: [String] = []
}

enum Trash {
    /// Déplace vers la corbeille (jamais de suppression définitive).
    static func move(_ entries: [(URL, Int64)]) -> TrashReport {
        var r = TrashReport()
        for (url, size) in entries {
            guard Safety.canTrash(url) else {
                r.failures.append("\(url.lastPathComponent) : emplacement protégé")
                continue
            }
            do {
                try FS.fm.trashItem(at: url, resultingItemURL: nil)
                r.moved += 1
                r.freed += size
            } catch {
                r.failures.append("\(url.lastPathComponent) : \(error.localizedDescription)")
            }
        }
        return r
    }
}
