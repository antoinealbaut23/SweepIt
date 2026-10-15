import SwiftUI

struct ModuleHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .glassCircle(tint: .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            GlassGroup {
                HStack(spacing: 8) { actions }
                    .glassButtonStyle()
            }
        }
        .padding(20)
    }
}

/// Barre du bas : résumé de la sélection + bouton de mise à la corbeille avec confirmation.
struct TrashBar: View {
    let count: Int
    let size: Int64
    var label = "Mettre à la corbeille"
    let action: () -> Void
    @State private var confirm = false

    var body: some View {
        GlassGroup {
            HStack {
                Text("\(count) élément\(count > 1 ? "s" : "") sélectionné\(count > 1 ? "s" : "") · \(Fmt.bytes(size))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .glassCapsule()
                Spacer()
                Button(role: .destructive) { confirm = true } label: {
                    Label(label, systemImage: "trash")
                }
                .controlSize(.large)
                .glassButtonStyle(prominent: true)
                .disabled(count == 0)
            }
        }
        .glassBottomBar()
        .confirmationDialog("Mettre \(count) élément\(count > 1 ? "s" : "") à la corbeille ?",
                            isPresented: $confirm) {
            Button(label, role: .destructive, action: action)
        } message: {
            Text("\(Fmt.bytes(size)) seront déplacés dans la corbeille. Vous pourrez les restaurer tant qu'elle n'est pas vidée.")
        }
    }
}

struct FolderPickerButton: View {
    @Binding var url: URL

    var body: some View {
        Button {
            if let u = FS.pickFolder(start: url) { url = u }
        } label: {
            Label(url.path.replacingOccurrences(of: Safety.home.path, with: "~"), systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)
        }
    }
}

struct ScanningView: View {
    let text: String
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).foregroundStyle(.secondary).monospacedDigit()
            if let onCancel { Button("Annuler", action: onCancel) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    func trashReportAlert(_ report: Binding<TrashReport?>) -> some View {
        alert("Terminé",
              isPresented: Binding(get: { report.wrappedValue != nil },
                                   set: { if !$0 { report.wrappedValue = nil } }),
              presenting: report.wrappedValue) { _ in
            Button("OK") {}
            Button("Ouvrir la corbeille") {
                NSWorkspace.shared.open(Safety.home.appendingPathComponent(".Trash"))
            }
        } message: { r in
            Text(r.message)
        }
    }

}

extension TrashReport {
    var message: String {
        let r = self
        var msg = "\(r.moved) élément\(r.moved > 1 ? "s" : "") placé\(r.moved > 1 ? "s" : "") dans la corbeille (\(Fmt.bytes(r.freed))). Videz la corbeille pour libérer réellement l'espace."
        if !r.failures.isEmpty {
            msg += "\n\n\(r.failures.count) échec\(r.failures.count > 1 ? "s" : "") :\n"
            msg += r.failures.prefix(5).joined(separator: "\n")
            if r.failures.count > 5 { msg += "\n…" }
        }
        return msg
    }
}
