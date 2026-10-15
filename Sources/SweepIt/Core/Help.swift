import SwiftUI

enum RiskLevel {
    case safe, review, info

    var label: String {
        switch self {
        case .safe: "Sans risque"
        case .review: "À vérifier"
        case .info: "Aucune suppression"
        }
    }
    var icon: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .review: "eye.fill"
        case .info: "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .info: .blue
        }
    }
}

struct ModuleHelp {
    let what: String
    let when: String
    let risk: String
    let level: RiskLevel
}

extension Module {
    /// Sous-titre affiché dans la barre latérale.
    var tagline: String {
        switch self {
        case .cleaner: "Fichiers inutiles"
        case .largeFiles: "Ce qui prend de la place"
        case .diskMap: "Carte de votre disque"
        case .desktop: "Ranger votre Bureau"
        case .uninstaller: "Retirer une app proprement"
        case .duplicates: "Fichiers en double"
        case .battery: "Santé de la batterie"
        case .monitor: "Santé du Mac"
        }
    }

    var help: ModuleHelp {
        switch self {
        case .cleaner:
            ModuleHelp(what: "Supprime les fichiers temporaires que votre Mac et vos apps accumulent avec le temps, un peu comme vider les miettes du grille-pain.",
                       when: "Quand votre disque est presque plein, ou une fois par mois.",
                       risk: "Ces fichiers se recréent tout seuls si une app en a besoin. Et tout passe par la corbeille.",
                       level: .safe)
        case .largeFiles:
            ModuleHelp(what: "Liste les fichiers les plus lourds de votre Mac : vieilles vidéos, installateurs oubliés dans Téléchargements, archives…",
                       when: "Pour faire du tri dans vos documents et téléchargements.",
                       risk: "Ce sont vos fichiers personnels : ne supprimez que ce que vous reconnaissez. Double-cliquez sur une ligne pour voir le fichier dans le Finder.",
                       level: .review)
        case .diskMap:
            ModuleHelp(what: "Montre en un coup d'œil ce qui occupe votre disque : plus un bloc est grand, plus il prend de place. Cliquez sur un bloc pour voir ce qu'il contient.",
                       when: "Pour comprendre où est passé votre espace.",
                       risk: "C'est une simple visite : rien n'est supprimé, sauf si vous le demandez avec un clic droit.",
                       level: .info)
        case .desktop:
            ModuleHelp(what: "Trie automatiquement les fichiers de votre Bureau (captures d'écran, documents, images, installateurs…) pour les ranger dans des dossiers ou les mettre à la corbeille.",
                       when: "Quand votre Bureau ressemble à un vide-poche.",
                       risk: "Les fichiers sont seulement déplacés, rien n'est effacé. Et le bouton « Annuler le rangement » remet tout comme avant.",
                       level: .safe)
        case .battery:
            ModuleHelp(what: "Fait le bilan de santé de votre batterie : niveau de charge, usure, nombre de cycles, avec des conseils pour la faire durer.",
                       when: "Si l'autonomie baisse, avant de revendre votre Mac, ou simplement par curiosité.",
                       risk: "Simple diagnostic, aucune action sur votre Mac.",
                       level: .info)
        case .uninstaller:
            ModuleHelp(what: "Supprime une application et tous les fichiers qu'elle a semés sur votre Mac (réglages, fichiers temporaires…). Glisser une app à la corbeille oublie souvent ces restes.",
                       when: "Pour une app que vous n'utilisez plus.",
                       risk: "Les réglages de l'app partent avec elle : si vous la réinstallez, elle repartira de zéro.",
                       level: .review)
        case .duplicates:
            ModuleHelp(what: "Trouve les fichiers présents en plusieurs exemplaires identiques, même s'ils ont des noms différents. Par exemple une photo téléchargée deux fois.",
                       when: "Après avoir importé des photos ou copié des dossiers d'un disque à l'autre.",
                       risk: "SweepIt garde toujours au moins un exemplaire de chaque fichier. Vérifiez quand même lequel vous conservez.",
                       level: .review)
        case .monitor:
            ModuleHelp(what: "Affiche en direct l'activité de votre Mac : le processeur (son « cerveau »), la mémoire (son « bureau de travail »), l'espace disque et la batterie.",
                       when: "Si votre Mac rame, chauffe ou fait du bruit.",
                       risk: "Simple affichage, aucune action sur vos fichiers.",
                       level: .info)
        }
    }
}

struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Label(level.label, systemImage: level.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(level.color.opacity(0.12), in: Capsule())
    }
}

/// Encadré « Comment ça marche ? » en haut de chaque module, repliable.
struct HelpCard: View {
    let module: Module
    @AppStorage private var collapsed: Bool

    init(module: Module) {
        self.module = module
        _collapsed = AppStorage(wrappedValue: false, "help.collapsed.\(module.rawValue)")
    }

    var body: some View {
        let help = module.help
        Group {
            if collapsed {
                Button { withAnimation(.snappy) { collapsed = false } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                        Text("Comment ça marche ?")
                        Spacer()
                        RiskBadge(level: help.level)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    row("sparkle.magnifyingglass", "Ce que ça fait", help.what)
                    row("calendar", "Quand l'utiliser", help.when)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: help.level.icon).foregroundStyle(help.level.color).frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            RiskBadge(level: help.level)
                            Text(help.risk).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("J'ai compris") { withAnimation(.snappy) { collapsed = true } }
                            .controlSize(.small)
                    }
                }
                .padding(14)
                .glassCard(tint: .accentColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        Divider()
    }

    private func row(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}

/// Petit bouton ⓘ qui affiche une explication dans une bulle.
struct InfoButton: View {
    let title: String
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("En savoir plus")
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 320)
        }
    }
}
