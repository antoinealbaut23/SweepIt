import SwiftUI

/// Langage visuel « Liquid Glass » (macOS 26), avec repli sur les matériaux et styles
/// classiques pour macOS 14 à 25. Tous les `#available` de l'app sont rassemblés ici.
enum GlassMetrics {
    /// Coins des cartes (Moniteur, Batterie, Bureau, aide…).
    static let cardRadius: CGFloat = 16
    /// Coins des petits encadrés (bandeaux, listes de détails).
    static let smallRadius: CGFloat = 12
    /// Distance en dessous de laquelle deux éléments en verre fusionnent dans un `GlassGroup`.
    /// Plus petite que l'espacement des grilles, pour que les cartes restent séparées.
    static let groupSpacing: CGFloat = 8
}

extension View {
    /// Carte en verre, éventuellement teintée. Repli : fond gris léger (ou teinté) aux coins arrondis.
    /// Ne pas placer une carte en verre dans une autre.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = GlassMetrics.cardRadius, tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint?.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(tint.map { AnyShapeStyle($0.opacity(0.1)) } ?? AnyShapeStyle(.quaternary.opacity(0.45)),
                       in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Pastille ronde en verre teinté (icônes, numéros d'étape). Repli : disque de couleur.
    @ViewBuilder
    func glassCircle(tint: Color, strong: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(strong ? tint : tint.opacity(0.25)), in: Circle())
        } else {
            background(strong ? tint : tint.opacity(0.12), in: Circle())
        }
    }

    /// Petite capsule en verre autour d'un texte (résumé d'une barre d'action). Repli : rien.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26, *) {
            padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
        } else {
            self
        }
    }

    /// Barre d'action en bas d'un écran. macOS 26 : pas de bandeau, ses éléments sont en verre
    /// (`glassCapsule`, `glassButtonStyle`). Repli : bandeau `.bar` sur toute la largeur.
    @ViewBuilder
    func glassBottomBar() -> some View {
        if #available(macOS 26, *) {
            padding(.horizontal, 16)
                .padding(.vertical, 10)
        } else {
            padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    /// Bouton en verre (`.glass`), ou en verre teinté pour l'action principale (`.glassProminent`).
    /// Repli : style par défaut, ou `.borderedProminent` pour l'action principale.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { self }
        }
    }
}

/// Regroupe des éléments en verre proches (`GlassEffectContainer`) pour qu'ils se rendent
/// ensemble et se fondent les uns dans les autres. Repli : le contenu tel quel.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = GlassMetrics.groupSpacing
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
