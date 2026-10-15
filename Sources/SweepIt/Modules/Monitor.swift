import Darwin
import IOKit.ps
import SwiftUI

struct BatteryInfo {
    let percent: Int
    let charging: Bool
    let onAC: Bool
}

enum SystemStats {
    struct CPUTicks { let busy: UInt64; let total: UInt64 }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(busy: user + system + nice, total: user + system + nice + idle)
    }

    /// Même calcul que « Mémoire utilisée » dans le Moniteur d'activité.
    static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    static func disk() -> (free: Int64, total: Int64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys)
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }

    static func battery() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return BatteryInfo(percent: max > 0 ? cur * 100 / max : 0,
                               charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                               onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }
}

@Observable @MainActor
final class SystemMonitor {
    var cpu: Double = 0
    var cpuHistory: [Double] = []
    var memUsed: UInt64 = 0
    let memTotal = ProcessInfo.processInfo.physicalMemory
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var battery: BatteryInfo?

    private var lastTicks: SystemStats.CPUTicks?
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var memFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }
    var diskFraction: Double { diskTotal > 0 ? 1 - Double(diskFree) / Double(diskTotal) : 0 }

    func refresh() {
        if let t = SystemStats.cpuTicks() {
            if let last = lastTicks, t.total > last.total {
                cpu = Double(t.busy - last.busy) / Double(t.total - last.total)
                cpuHistory.append(cpu)
                if cpuHistory.count > 60 { cpuHistory.removeFirst() }
            }
            lastTicks = t
        }
        memUsed = SystemStats.memoryUsed()
        (diskFree, diskTotal) = SystemStats.disk()
        battery = SystemStats.battery()
    }
}

// MARK: - Vues

struct Ring: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard values.count > 1 else { return }
                let step = geo.size.width / CGFloat(59)
                let offset = CGFloat(60 - values.count) * step
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: offset + CGFloat(i) * step, y: geo.size.height * (1 - v))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: Double
    let main: String
    let detail: String
    let color: Color
    var hint = ""

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Ring(value: value, color: color, lineWidth: 12)
                Text(main).font(.title2.bold()).monospacedDigit()
            }
            .frame(width: 120, height: 120)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if !hint.isEmpty {
                Text(hint).font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

private func gib(_ b: UInt64) -> String { String(format: "%.1f Go", Double(b) / 1_073_741_824) }

struct MonitorView: View {
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Moniteur", subtitle: "L'état de santé de votre Mac, en direct.",
                         icon: "gauge.with.dots.needle.67percent") { EmptyView() }
            Divider()
            HelpCard(module: .monitor)
            ScrollView {
                GlassGroup {
                    VStack(spacing: 20) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                            StatCard(title: "Processeur", value: m.cpu, main: "\(Int(m.cpu * 100)) %",
                                     detail: "\(ProcessInfo.processInfo.activeProcessorCount) cœurs", color: .blue,
                                     hint: "L'effort de réflexion de votre Mac en ce moment.")
                            StatCard(title: "Mémoire", value: m.memFraction, main: "\(Int(m.memFraction * 100)) %",
                                     detail: "\(gib(m.memUsed)) / \(gib(m.memTotal))", color: .purple,
                                     hint: "L'espace de travail des apps ouvertes.")
                            StatCard(title: "Disque", value: m.diskFraction, main: "\(Int(m.diskFraction * 100)) %",
                                     detail: "\(Fmt.bytes(m.diskFree)) libres", color: .orange,
                                     hint: "Le rangement de vos fichiers.")
                            if let b = m.battery {
                                StatCard(title: "Batterie", value: Double(b.percent) / 100, main: "\(b.percent) %",
                                         detail: b.charging ? "En charge" : (b.onAC ? "Sur secteur" : "Sur batterie"),
                                         color: .green)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Processeur — 2 dernières minutes").font(.headline)
                            Sparkline(values: m.cpuHistory, color: .blue)
                                .frame(height: 80)
                                .padding(12)
                                .glassCard(cornerRadius: GlassMetrics.smallRadius)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

struct MonitorMenuView: View {
    @Environment(SystemMonitor.self) private var m
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("cpu", "Processeur", "\(Int(m.cpu * 100)) %", m.cpu, .blue)
            Sparkline(values: m.cpuHistory, color: .blue).frame(height: 28)
            row("memorychip", "Mémoire", "\(gib(m.memUsed)) / \(gib(m.memTotal))", m.memFraction, .purple)
            row("internaldrive", "Disque", "\(Fmt.bytes(m.diskFree)) libres", m.diskFraction, .orange)
            if let b = m.battery {
                row(b.charging ? "battery.100percent.bolt" : "battery.75percent", "Batterie",
                    "\(b.percent) %", Double(b.percent) / 100, .green)
            }
            Divider()
            HStack {
                Button("Ouvrir SweepIt") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func row(_ icon: String, _ title: String, _ value: String, _ fraction: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1)).tint(color)
        }
    }
}
