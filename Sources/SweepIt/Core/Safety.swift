import AppKit
import Foundation

/// Garde-fous : tout ce qui part à la corbeille passe par `canTrash`.
enum Safety {
    static let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL

    /// Dossiers qu'on ne supprime jamais eux-mêmes (leur contenu peut l'être).
    private static let protectedPaths: Set<String> = {
        let h = home.path
        var s: Set<String> = ["/", "/Applications", "/Users", "/Library", "/System", h]
        for d in ["Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music",
                  "Applications", "Public", ".Trash"] {
            s.insert(h + "/" + d)
        }
        for d in ["Caches", "Preferences", "Application Support", "Containers", "Group Containers",
                  "Logs", "Mobile Documents", "Developer", "LaunchAgents", "Saved Application State",
                  "HTTPStorages", "WebKit", "Cookies", "Application Scripts", "Mail", "Messages"] {
            s.insert(h + "/Library/" + d)
        }
        return s
    }()

    /// Arborescences entièrement intouchables.
    private static let protectedPrefixes = [home.path + "/Library/Keychains/", "/System/"]

    /// Dossiers ignorés par les scans de fichiers (gros fichiers, doublons).
    static let scanExclusions: Set<String> = [
        home.path + "/Library", home.path + "/.Trash",
        "/System", "/private", "/dev", "/Volumes", "/cores",
    ]

    static func canTrash(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        if protectedPaths.contains(p) { return false }
        if protectedPrefixes.contains(where: { p.hasPrefix($0) }) { return false }
        return p.hasPrefix(home.path + "/") || p.hasPrefix("/Applications/")
    }
}

enum Permissions {
    /// Emplacements lisibles uniquement avec l'accès complet au disque.
    /// Plusieurs témoins, car leur présence varie selon la version de macOS
    /// (le TCC.db utilisateur, par exemple, n'existe plus sur macOS 27).
    private static let probes: [String] = [
        "/Library/Application Support/com.apple.TCC/TCC.db",
        Safety.home.path + "/Library/Safari",
        Safety.home.path + "/Library/Mail",
        Safety.home.path + "/Library/Messages",
        Safety.home.path + "/Library/Containers/com.apple.stocks",
    ]

    static var hasFullDiskAccess: Bool {
        let fm = FileManager.default
        for path in probes {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if (try? fm.contentsOfDirectory(atPath: path)) != nil { return true }
            } else if let h = FileHandle(forReadingAtPath: path) {
                try? h.close()
                return true
            }
        }
        return false
    }

    /// Relance l'app (l'accès complet au disque ne s'applique qu'au redémarrage).
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
