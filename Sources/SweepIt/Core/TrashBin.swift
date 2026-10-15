import SwiftUI

/// Commandes envoyées au Finder. Il gère lui-même la demande de mot de passe
/// administrateur pour les éléments protégés (apps installées par un .pkg, par exemple).
enum Finder {
    /// Lance un AppleScript et attend la fin. Renvoie nil si tout s'est bien passé, sinon le message d'erreur.
    static func run(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        do { try p.run() } catch { return error.localizedDescription }
        p.waitUntilExit()
        guard p.terminationStatus != 0 else { return nil }
        let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // -128 : l'utilisateur a annulé la demande de mot de passe.
        return msg.contains("-128") ? "annulé" : msg.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Met à la corbeille via le Finder (avec demande de mot de passe si nécessaire).
    static func trash(_ url: URL) -> String? {
        let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return run("tell application \"Finder\" to delete (POSIX file \"\(path)\" as alias)")
    }
}

enum TrashBin {
    static let url = Safety.home.appendingPathComponent(".Trash")

    struct Info: Equatable {
        var count = 0
        var bytes: Int64 = 0
    }

    static func info() -> Info {
        let items = FS.children(url).filter { $0.lastPathComponent != ".DS_Store" }
        return Info(count: items.count, bytes: items.reduce(0) { $0 + FS.allocatedSize($1) })
    }

    /// Suppression définitive, via le Finder (gère aussi les éléments protégés).
    static func empty() -> String? {
        Finder.run("tell application \"Finder\" to empty trash")
    }

    /// Demande au widget de la barre latérale d'afficher la confirmation pour vider la corbeille.
    static let emptyRequest = Notification.Name("SweepIt.emptyTrashRequest")
}

/// Ligne « Corbeille » en bas de la barre latérale, avec le bouton Vider.
struct TrashWidget: View {
    @State private var info = TrashBin.Info()
    @State private var confirm = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: info.count > 0 ? "trash.fill" : "trash")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Corbeille").font(.callout)
                Text(info.count == 0 ? "Vide" : "\(Fmt.bytes(info.bytes)) · \(info.count) élément\(info.count > 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if working {
                ProgressView().controlSize(.small)
            } else {
                Button("Vider") { confirm = true }
                    .controlSize(.small)
                    .disabled(info.count == 0)
            }
        }
        .padding(.horizontal, 6)
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TrashBin.emptyRequest)) { _ in
            Task {
                await refresh()
                if info.count > 0 { confirm = true }
            }
        }
        .confirmationDialog("Vider la corbeille ?", isPresented: $confirm) {
            Button("Vider la corbeille", role: .destructive) { empty() }
        } message: {
            Text("\(info.count) élément\(info.count > 1 ? "s" : "") (\(Fmt.bytes(info.bytes))) seront supprimés définitivement. Vous ne pourrez plus les récupérer.")
        }
        .alert("La corbeille n'a pas pu être vidée",
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    private func refresh() async {
        info = await Task.detached(priority: .utility) { TrashBin.info() }.value
    }

    private func empty() {
        working = true
        Task {
            let result = await Task.detached { TrashBin.empty() }.value
            if let result, result != "annulé" { error = result }
            await refresh()
            working = false
        }
    }
}
