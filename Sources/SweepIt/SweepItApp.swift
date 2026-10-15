import SwiftUI

@main
struct SweepItApp: App {
    @State private var monitor = SystemMonitor()

    var body: some Scene {
        Window("SweepIt", id: "main") {
            ContentView()
                .environment(monitor)
                // Fond en verre blanc : l'app reste en apparence claire pour que le texte soit lisible.
                .preferredColorScheme(.light)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MonitorMenuView().environment(monitor)
        } label: {
            Image(systemName: "sparkles")
            Text("\(Int(monitor.cpu * 100)) %")
        }
        .menuBarExtraStyle(.window)
    }
}
