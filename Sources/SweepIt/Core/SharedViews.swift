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
        alert(report.wrappedValue?.title ?? "Terminé",
              isPresented: Binding(get: { report.wrappedValue != nil },
                                   set: { if !$0 { report.wrappedValue = nil } }),
              presenting: report.wrappedValue) { r in
            Button("OK") {}
            if r.moved > 0 {
                Button("Vider la corbeille…") {
                    NotificationCenter.default.post(name: TrashBin.emptyRequest, object: nil)
                }
            }
        } message: { r in
            Text(r.message)
        }
    }

}

extension TrashReport {
    var title: String { moved == 0 && !failures.isEmpty ? "Rien n'a pu être supprimé" : "Terminé" }

    var message: String {
        let r = self
        guard r.moved > 0 else { return failureDetails }
        var msg = "\(r.moved) élément\(r.moved > 1 ? "s" : "") placé\(r.moved > 1 ? "s" : "") dans la corbeille (\(Fmt.bytes(r.freed))). Videz la corbeille pour libérer réellement l'espace."
        if !r.failures.isEmpty { msg += "\n\n" + failureDetails }
        return msg
    }

    private var failureDetails: String {
        var msg = "\(failures.count) échec\(failures.count > 1 ? "s" : "") :\n" + failures.prefix(5).joined(separator: "\n")
        if failures.count > 5 { msg += "\n…" }
        return msg
    }
}
