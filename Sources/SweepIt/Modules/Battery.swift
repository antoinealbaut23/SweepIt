import IOKit
import IOKit.ps
import SwiftUI

// MARK: - Lecture

struct BatteryReport {
    let percent: Int
    let isCharging: Bool
    let pluggedIn: Bool
    let cycleCount: Int
    let designCycles: Int
    let designCapacity: Int      // mAh, neuve
    let maxCapacity: Int         // mAh, aujourd'hui
    let temperature: Double?     // °C, pas exposée sur tous les Mac
    let minutesLeft: Int?
    let adapterWatts: Int?
    let condition: String?       // état indiqué par macOS (« Good », « Check Battery »…)

    /// Capacité maximale actuelle par rapport à la batterie neuve (0…1).
    var health: Double? {
        guard designCapacity > 0, maxCapacity > 0 else { return nil }
        return min(Double(maxCapacity) / Double(designCapacity), 1)
    }
    var cycleRatio: Double { designCycles > 0 ? Double(cycleCount) / Double(designCycles) : 0 }
    var conditionIsGood: Bool { condition == nil || condition == "Good" }
}

enum BatteryReader {
    static func read() -> BatteryReport? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }
        let data = d["BatteryData"] as? [String: Any] ?? [:]

        // Selon les Mac, les valeurs sont à la racine ou dans « BatteryData ».
        func int(_ keys: String...) -> Int? {
            for k in keys {
                if let n = (d[k] ?? data[k]) as? NSNumber { return n.intValue }
            }
            return nil
        }
        func bool(_ k: String) -> Bool { ((d[k] ?? data[k]) as? NSNumber)?.boolValue ?? false }

        let ps = SystemStats.battery()
        let rawMax = int("MaxCapacity") ?? 100
        // Sur Apple Silicon, MaxCapacity/CurrentCapacity sont des pourcentages, les mAh sont ailleurs.
        let maxMAh = int("NominalChargeCapacity", "AppleRawMaxCapacity") ?? (rawMax > 100 ? rawMax : 0)
        let percent = ps?.percent ?? int("CurrentCapacity") ?? 0
        let minutes = int("TimeRemaining", "AvgTimeToEmpty").flatMap { ($0 > 0 && $0 < 65535) ? $0 : nil }
        let adapter = ((d["AdapterDetails"] ?? d["AppleRawAdapterDetails"]) as? [String: Any])?["Watts"] as? Int

        return BatteryReport(percent: percent,
                             isCharging: bool("IsCharging"),
                             pluggedIn: bool("ExternalConnected"),
                             cycleCount: int("CycleCount") ?? 0,
                             designCycles: int("DesignCycleCount9C") ?? 1000,
                             designCapacity: int("DesignCapacity") ?? 0,
                             maxCapacity: maxMAh,
                             temperature: int("Temperature").map { Double($0) / 100 },
                             minutesLeft: minutes,
                             adapterWatts: adapter,
                             condition: powerSourceHealth())
    }

    /// L'état affiché par macOS dans Réglages › Batterie.
    private static func powerSourceHealth() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
               let health = d[kIOPSBatteryHealthKey] as? String {
                return health
            }
        }
        return nil
    }
}

// MARK: - Conseils

struct BatteryTip: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let text: String
}

extension BatteryReport {
    var tips: [BatteryTip] {
        var out: [BatteryTip] = []

        if !conditionIsGood {
            out.append(BatteryTip(icon: "exclamationmark.triangle.fill", color: .red,
                                  title: "macOS signale un problème",
                                  text: "Réglages › Batterie indique que la batterie doit être vérifiée. Un Apple Store ou un réparateur agréé peut la contrôler et la remplacer."))
        }

        if let h = health {
            let pct = Int((h * 100).rounded())
            if h >= 0.8 {
                out.append(BatteryTip(icon: "heart.fill", color: .green, title: "Batterie en bonne santé",
                                      text: "Elle garde \(pct) % de sa capacité d'origine. Rien à faire !"))
            } else if h >= 0.7 {
                out.append(BatteryTip(icon: "heart.slash", color: .orange, title: "Capacité en baisse",
                                      text: "Elle ne garde plus que \(pct) % de sa capacité d'origine. Apple considère qu'une batterie est usée sous 80 % : elle marche encore, mais l'autonomie est réduite."))
            } else {
                out.append(BatteryTip(icon: "battery.0percent", color: .red, title: "Remplacement conseillé",
                                      text: "Avec \(pct) % de sa capacité d'origine, l'autonomie est fortement réduite. Un remplacement redonnerait une vraie seconde vie à votre Mac."))
            }
        }

        if cycleRatio >= 0.8 {
            out.append(BatteryTip(icon: "arrow.triangle.2.circlepath", color: .orange, title: "Beaucoup de cycles",
                                  text: "\(cycleCount) cycles sur environ \(designCycles) prévus. La batterie approche de la fin de sa durée de vie normale."))
        } else {
            out.append(BatteryTip(icon: "arrow.triangle.2.circlepath", color: .blue, title: "Il reste de la marge",
                                  text: "\(cycleCount) cycles sur environ \(designCycles) prévus par Apple : votre batterie a encore de beaux jours devant elle."))
        }

        if let t = temperature, t > 40 {
            out.append(BatteryTip(icon: "thermometer.high", color: .orange, title: "Batterie chaude (\(Int(t)) °C)",
                                  text: "La chaleur use la batterie. Évitez de poser le Mac sur un lit ou un coussin, et retirez une coque épaisse pendant la charge."))
        }

        if pluggedIn && percent >= 95 {
            out.append(BatteryTip(icon: "powerplug", color: .blue, title: "Souvent branché ?",
                                  text: "Vérifiez que la « Recharge optimisée » est activée dans Réglages › Batterie : macOS retient alors la charge à 80 % quand c'est utile, ce qui ralentit l'usure."))
        } else if !pluggedIn && percent <= 20 {
            out.append(BatteryTip(icon: "battery.25percent", color: .orange, title: "Batterie faible",
                                  text: "Branchez votre Mac bientôt. En attendant, le mode Économie d'énergie (Réglages › Batterie) prolonge l'autonomie."))
        }

        out.append(BatteryTip(icon: "lightbulb", color: .yellow, title: "Les bons réflexes",
                              text: "Évitez la chaleur extrême (voiture au soleil), gardez macOS à jour, et ne laissez pas la batterie vide pendant des jours."))
        return out
    }
}

// MARK: - Vue

struct BatteryView: View {
    @State private var report: BatteryReport?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Batterie", subtitle: "Santé de votre batterie et conseils pour la faire durer.",
                         icon: "battery.75percent") {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Label("Réglages Batterie", systemImage: "gearshape") }
            }
            Divider()
            HelpCard(module: .battery)

            if !loaded {
                ScanningView(text: "Lecture de la batterie…")
            } else if let r = report {
                ScrollView {
                    GlassGroup {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(spacing: 16) {
                                chargeCard(r)
                                healthCard(r)
                                cyclesCard(r)
                            }
                            details(r)
                            Text("Recommandations").font(.title3.bold())
                            VStack(spacing: 10) {
                                ForEach(r.tips) { tipRow($0) }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView("Pas de batterie", systemImage: "desktopcomputer",
                                       description: Text("Ce Mac est un ordinateur de bureau : il fonctionne sur secteur et n'a pas de batterie."))
            }
        }
        .task {
            while !Task.isCancelled {
                report = BatteryReader.read()
                loaded = true
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    // MARK: Cartes

    private func chargeCard(_ r: BatteryReport) -> some View {
        let status: String = r.isCharging ? "En charge"
            : r.pluggedIn ? "Branché, charge terminée"
            : r.minutesLeft.map { "Environ \($0 / 60) h \(String(format: "%02d", $0 % 60)) restantes" } ?? "Sur batterie"
        return BatteryCard(title: "Charge", value: Double(r.percent) / 100, main: "\(r.percent) %",
                           detail: status, color: r.percent <= 20 ? .orange : .green,
                           info: "Le niveau de charge actuel, comme dans la barre de menus.")
    }

    private func healthCard(_ r: BatteryReport) -> some View {
        let h = r.health ?? 0
        let label = r.health == nil ? "Inconnue" : h >= 0.8 ? "Bonne" : h >= 0.7 ? "Correcte" : "Usée"
        let detail = r.health == nil ? "Non communiquée par ce Mac"
            : "\(label) · \(r.maxCapacity) / \(r.designCapacity) mAh"
        return BatteryCard(title: "Santé", value: h, main: r.health == nil ? "—" : "\(Int((h * 100).rounded())) %",
                           detail: detail, color: h >= 0.8 ? .green : h >= 0.7 ? .orange : .red,
                           info: "Ce que la batterie peut stocker aujourd'hui, comparé à quand elle était neuve. Toutes les batteries s'usent avec le temps : sous 80 %, Apple la considère comme usée.")
    }

    private func cyclesCard(_ r: BatteryReport) -> some View {
        BatteryCard(title: "Cycles", value: r.cycleRatio, main: "\(r.cycleCount)",
                    detail: "sur ~\(r.designCycles) prévus", color: r.cycleRatio >= 0.8 ? .orange : .blue,
                    info: "Un cycle, c'est 100 % de batterie consommés, même en plusieurs fois : utiliser 50 % aujourd'hui et 50 % demain fait un cycle. Apple prévoit environ \(r.designCycles) cycles avant que la batterie ne s'use vraiment.")
    }

    private func details(_ r: BatteryReport) -> some View {
        HStack(spacing: 24) {
            detailItem("powerplug", "Chargeur",
                       r.pluggedIn ? (r.adapterWatts.map { "Branché · \($0) W" } ?? "Branché") : "Non branché")
            if let t = r.temperature {
                detailItem("thermometer.medium", "Température", String(format: "%.0f °C", t))
            }
            detailItem(r.conditionIsGood ? "checkmark.shield" : "exclamationmark.triangle", "État selon macOS",
                       r.conditionIsGood ? "Normal" : "Vérification recommandée")
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: GlassMetrics.smallRadius)
    }

    private func detailItem(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).bold()
            }
        }
    }

    private func tipRow(_ tip: BatteryTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .foregroundStyle(tip.color)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(tip.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(tip.title).font(.headline)
                Text(tip.text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(cornerRadius: GlassMetrics.smallRadius)
    }
}

private struct BatteryCard: View {
    let title: String
    let value: Double
    let main: String
    let detail: String
    let color: Color
    let info: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(title).font(.headline)
                InfoButton(title: title, text: info)
            }
            ZStack {
                Ring(value: value, color: color, lineWidth: 12)
                Text(main).font(.title.bold()).monospacedDigit()
            }
            .frame(width: 120, height: 120)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}
