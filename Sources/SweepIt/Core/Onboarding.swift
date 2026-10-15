import SwiftUI

/// Guide de démarrage : présentation, puis accès complet au disque pas à pas.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding.done") private var done = false
    @State var step: Int
    @State private var granted = Permissions.hasFullDiskAccess
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: why
                case 2: howTo
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity))

            footer
        }
        .frame(width: 600, height: 560)
        .onReceive(poll) { _ in granted = Permissions.hasFullDiskAccess }
    }

    // MARK: Étapes

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            Text("Bienvenue dans SweepIt").font(.largeTitle.bold())
            Text("Le petit coup de balai dont votre Mac a besoin.")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                bullet("sparkles", .purple, "Libérez de la place", "en retirant les fichiers inutiles.")
                bullet("xmark.app", .pink, "Désinstallez proprement", "les apps dont vous ne vous servez plus.")
                bullet("gauge.with.dots.needle.67percent", .blue, "Surveillez votre Mac", "depuis la barre de menus.")
                bullet("arrow.uturn.backward.circle", .green, "Zéro mauvaise surprise :",
                       "rien n'est supprimé sans votre accord, et tout passe par la corbeille.")
            }
            .padding(.top, 8)
        }
    }

    private var why: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.fill")
                .font(.system(size: 52)).foregroundStyle(.orange)
                .frame(width: 100, height: 100)
                .glassCircle(tint: .orange)
            Text("Une autorisation à donner").font(.title.bold())
            Text("Imaginez un agent d'entretien : pour nettoyer toute la maison, il a besoin des clés de chaque pièce.\n\nC'est pareil ici : macOS protège certains dossiers. Pour les voir et les nettoyer, SweepIt a besoin de l'**accès complet au disque**.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label("SweepIt n'envoie rien sur Internet.", systemImage: "wifi.slash")
                Label("Il ne supprime rien sans vous demander.", systemImage: "hand.raised")
                Label("Vous pouvez retirer l'accès à tout moment.", systemImage: "arrow.uturn.backward")
            }
            .foregroundStyle(.secondary)
            .padding(14)
            .glassCard(cornerRadius: GlassMetrics.smallRadius)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Donner l'accès en 3 étapes").font(.title.bold()).frame(maxWidth: .infinity)

            stepRow(1, "Ouvrez les Réglages Système") {
                Button { Permissions.openFullDiskAccessSettings() } label: {
                    Label("Ouvrir les Réglages", systemImage: "gearshape")
                }
                .glassButtonStyle(prominent: true)
            }

            stepRow(2, "Activez l'interrupteur à côté de SweepIt") {
                VStack(alignment: .leading, spacing: 8) {
                    settingsMockup
                    Text("SweepIt n'est pas dans la liste ? Faites-le glisser dedans depuis le Finder :")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Montrer SweepIt dans le Finder") { FS.reveal([Bundle.main.bundleURL]) }
                        .controlSize(.small)
                }
            }

            stepRow(3, "Acceptez de quitter et rouvrir SweepIt") {
                Text("macOS vous le proposera : c'est normal, l'autorisation s'applique au redémarrage de l'app.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            statusBanner
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            Image(systemName: granted ? "checkmark.seal.fill" : "hand.thumbsup.fill")
                .font(.system(size: 64)).foregroundStyle(granted ? .green : .blue)
            Text("Tout est prêt !").font(.largeTitle.bold())
            if !granted {
                Text("Sans l'accès complet, certaines analyses seront incomplètes. Vous pourrez le donner plus tard depuis le bouton en bas de la barre latérale.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                bullet("1.circle.fill", .purple, "Commencez par « Nettoyage » :", "c'est le plus simple et sans risque.")
                bullet("questionmark.circle.fill", .blue, "Un doute ?", "Chaque écran a un encadré « Comment ça marche ? ».")
                bullet("info.circle.fill", .teal, "Les petits ⓘ", "expliquent chaque élément en détail.")
            }
            .padding(.top, 8)
        }
    }

    // MARK: Éléments

    private var footer: some View {
        GlassGroup {
            HStack {
                if step > 0 && step < lastStep {
                    Button("Plus tard") { finish() }.buttonStyle(.link)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0...lastStep, id: \.self) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 && step < lastStep {
                    Button("Retour") { go(step - 1) }
                        .glassButtonStyle()
                }
                Button(nextLabel) { next() }
                    .glassButtonStyle(prominent: true)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .glassBottomBar()
    }

    private var nextLabel: String {
        switch step {
        case 0: "Commencer"
        case lastStep: "C'est parti !"
        case 2: granted ? "Continuer" : "Je le ferai plus tard"
        default: "Suivant"
        }
    }

    private var settingsMockup: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
            Text("SweepIt")
            Spacer()
            Toggle("", isOn: .constant(true)).toggleStyle(.switch).labelsHidden().allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .frame(maxWidth: 300)
    }

    @ViewBuilder
    private var statusBanner: some View {
        HStack(spacing: 10) {
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Accès accordé, merci !").bold()
            } else {
                ProgressView().controlSize(.small)
                Text("En attente de l'autorisation…").foregroundStyle(.secondary)
                Spacer()
                Button("Relancer SweepIt") { Permissions.relaunch() }.controlSize(.small)
            }
            Spacer()
        }
        .padding(12)
        .glassCard(cornerRadius: GlassMetrics.smallRadius, tint: granted ? .green : .orange)
    }

    private func bullet(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            (Text(title).bold() + Text(" " + text)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepRow<Content: View>(_ n: Int, _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.headline).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .glassCircle(tint: .accentColor, strong: true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    // MARK: Navigation

    private func go(_ s: Int) { withAnimation(.snappy) { step = s } }

    private func next() {
        switch step {
        case 1 where granted: go(lastStep)
        case lastStep: finish()
        default: go(step + 1)
        }
    }

    private func finish() {
        done = true
        dismiss()
    }
}
