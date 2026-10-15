# SweepIt

Utilitaire de nettoyage pour macOS, natif (Swift + SwiftUI), dans l'esprit de CleanMyMac.

Design : langage « Liquid Glass » de macOS 26 (cartes, barres d'action et boutons en verre, voir `Sources/SweepIt/Core/Glass.swift`), avec un repli sur les matériaux classiques de macOS 14 à 25.

| Module | Rôle |
|---|---|
| Nettoyage | Caches des apps, journaux, caches des navigateurs, Xcode (DerivedData, DeviceSupport), npm/Gradle/Cargo |
| Gros fichiers | Fichiers au-dessus d'une taille donnée, filtrables par ancienneté |
| Espace disque | Carte proportionnelle (treemap) navigable dossier par dossier |
| Désinstallateur | Supprime une app et ses restes dans `~/Library` |
| Doublons | Fichiers identiques au contenu (taille → hash partiel → SHA-256) |
| Moniteur | CPU, mémoire, disque, batterie, dans la fenêtre et la barre de menus |

## Sécurité

- Rien n'est supprimé définitivement : tout passe par la **corbeille**.
- Chaque suppression demande une confirmation.
- `Safety.canTrash` refuse tout ce qui est hors du dossier personnel et de `/Applications`, ainsi que les dossiers système (`~/Library/Caches` lui-même, `~/Documents`, trousseaux…).
- Les doublons gardent toujours au moins une copie.

## Compiler

Prérequis : macOS 14 ou plus, Xcode ou les Command Line Tools (`xcode-select --install`).

```bash
scripts/setup-signing.sh   # une seule fois
scripts/build-app.sh
open build/SweepIt.app
```

Pour développer, ouvrez `Package.swift` dans Xcode. Pour ouvrir directement un module : `open build/SweepIt.app --args -startModule battery`.

### Signature

macOS lie l'accès complet au disque à la signature de l'app. `scripts/setup-signing.sh` crée un certificat personnel « SweepIt Dev » dans un trousseau dédié (`~/.sweepit-signing`, le trousseau de session n'est pas touché). Tant que ce certificat ne change pas, l'accès accordé reste valable d'une version à l'autre, chez vous comme chez vos amis.

- **Sauvegardez `~/.sweepit-signing`** : sans lui, les versions suivantes auront une autre signature et l'accès devra être redonné partout.
- **Ne le publiez jamais** : il contient la clé privée.
- Sans ce certificat, `build-app.sh` signe « ad hoc » et l'accès est perdu à chaque recompilation.

## Publier une version

```bash
UNIVERSAL=1 scripts/make-dmg.sh
```

Produit `build/SweepIt-<version>.dmg` (Apple Silicon + Intel, signé) et son empreinte SHA-256. La version vient de `CFBundleShortVersionString` dans `Resources/Info.plist`. Les versions publiées sont sur la page [Releases](https://github.com/antoinealbaut23/SweepIt/releases).

## Partager avec des amis

Envoyez le DMG (ou le lien de la page Releases). L'app est signée avec un certificat personnel (pas un compte développeur Apple), donc au premier lancement macOS la bloque :

1. Double-cliquez sur SweepIt → message d'avertissement → **OK**.
2. **Réglages Système → Confidentialité et sécurité** → en bas, **Ouvrir quand même**.

Ou en une commande :

```bash
xattr -dr com.apple.quarantine /Applications/SweepIt.app
```

Ensuite, accordez l'**accès complet au disque** (Réglages Système → Confidentialité et sécurité → Accès complet au disque) pour que les analyses voient tout.

Pour une diffusion publique sans ces étapes, il faudra un compte Apple Developer (99 $/an) pour signer avec un certificat Developer ID et notariser l'app.

## Structure

```
Sources/SweepIt/
├── SweepItApp.swift        point d'entrée, fenêtre + barre de menus
├── ContentView.swift     barre latérale
├── Core/                 sécurité, accès fichiers, vues partagées
└── Modules/              un fichier par module (modèle + vue)
```

## Licence

MIT
