import SwiftUI

enum Module: String, CaseIterable, Identifiable {
    case cleaner, largeFiles, diskMap, desktop, uninstaller, duplicates, battery, monitor

    var id: Self { self }
    var title: String {
        switch self {
        case .cleaner: "Nettoyage"
        case .largeFiles: "Gros fichiers"
        case .diskMap: "Espace disque"
        case .desktop: "Organiseur de bureau"
        case .uninstaller: "Désinstallateur"
        case .duplicates: "Doublons"
        case .battery: "Batterie"
        case .monitor: "Moniteur"
        }
    }
    var icon: String {
        switch self {
        case .cleaner: "sparkles"
        case .largeFiles: "doc.badge.ellipsis"
        case .diskMap: "square.grid.3x3.square"
        case .desktop: "menubar.dock.rectangle"
        case .uninstaller: "xmark.app"
        case .duplicates: "doc.on.doc"
        case .battery: "battery.75percent"
        case .monitor: "gauge.with.dots.needle.67percent"
        }
    }
}

struct ContentView: View {
    // Lancement direct sur un module : open SweepIt.app --args -startModule battery
    @State private var module: Module? = Module(rawValue: UserDefaults.standard.string(forKey: "startModule") ?? "") ?? .cleaner
    @State private var cleaner = CleanerModel()
    @State private var largeFiles = LargeFilesModel()
    @State private var diskMap = DiskMapModel()
    @State private var uninstaller = UninstallerModel()
    @State private var duplicates = DuplicatesModel()
    @State private var desktop = DesktopModel()
    @State private var hasFDA = Permissions.hasFullDiskAccess
    @AppStorage("onboarding.done") private var onboardingDone = false
    /// Étape à laquelle ouvrir le guide (nil = fermé).
    @State private var guideStep: GuideRequest?

    var body: some View {
        NavigationSplitView {
            List(Module.allCases, selection: $module) { m in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.title)
                        Text(m.tagline).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: m.icon)
                }
                .padding(.vertical, 3)
                .tag(m)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !hasFDA { fdaBanner }
                    Button { guideStep = GuideRequest(step: 0) } label: {
                        Label("Guide de démarrage", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                }
                .padding(10)
            }
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch module ?? .cleaner {
                case .cleaner: CleanerView(model: cleaner)
                case .largeFiles: LargeFilesView(model: largeFiles)
                case .diskMap: DiskMapView(model: diskMap)
                case .desktop: DesktopView(model: desktop)
                case .uninstaller: UninstallerView(model: uninstaller)
                case .duplicates: DuplicatesView(model: duplicates)
                case .battery: BatteryView()
                case .monitor: MonitorView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Sans largeur minimale, SwiftUI calcule la hauteur minimale du contenu sur une colonne
            // très étroite : les textes s'empilent et la fenêtre déborde (contenu hors écran).
            .navigationSplitViewColumnWidth(min: 640, ideal: 860)
            // L'en-tête du module remonte tout en haut de la fenêtre, à la place de la barre de titre.
            .ignoresSafeArea(.container, edges: .top)
        }
        .toolbar(.hidden, for: .windowToolbar)
        .sheet(item: $guideStep) { request in
            OnboardingView(step: request.step)
        }
        .onAppear { if !onboardingDone { guideStep = GuideRequest(step: 0) } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFDA = Permissions.hasFullDiskAccess
        }
    }

    private var fdaBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accès limité", systemImage: "lock.shield").font(.headline)
            Text("SweepIt ne voit pas encore tous vos dossiers. Une autorisation suffit.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Me montrer comment") { guideStep = GuideRequest(step: 2) }
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: GlassMetrics.smallRadius, style: .continuous))
    }
}

struct GuideRequest: Identifiable {
    let step: Int
    var id: Int { step }
}
