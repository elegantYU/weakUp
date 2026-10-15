import Foundation

struct EngineSnapshot {
    var holding: Bool
    var status: String
    var battery: BatteryState
}

final class Engine {
    let store: Store
    let idle = IdleHold()
    var lidError: String?
    private var suppressLidRetry = false
    private let lidSupported: Bool
    private let commands: PowerCommanding

    init(store: Store, lidSupported: Bool, commands: PowerCommanding = LivePowerCommands()) {
        self.store = store
        self.lidSupported = lidSupported
        self.commands = commands
    }

    func restoreLidIfNeeded() {
        guard lidSupported, store.config.lidRestore?.active == true else { return }
        let previous = store.config.lidRestore?.previous ?? 0
        do {
            if commands.sleepDisabled() != previous {
                try commands.setSleepDisabled(previous)
            }
            store.update { $0.lidRestore = nil }
        } catch {
            lidError = error.localizedDescription
        }
    }

    func tick(runningPaths: Set<String>) -> EngineSnapshot {
        let config = store.config
        let battery = commands.battery()
        let selectedRunning = config.apps.contains { runningPaths.contains($0.path) }
        let hold = PolicyDecision.shouldHold(config: config, battery: battery, selectedRunning: selectedRunning)
        idle.set(on: hold)
        syncLid(want: hold && config.lidEnabled && lidSupported)
        let status = describe(config: config, battery: battery, hold: hold, selectedRunning: selectedRunning)
        return EngineSnapshot(holding: idle.isHolding, status: status, battery: battery)
    }

    func stop() {
        idle.stop()
        if lidSupported, store.config.lidRestore?.active == true {
            let previous = store.config.lidRestore?.previous ?? 0
            if (try? commands.setSleepDisabled(previous)) != nil {
                store.update { $0.lidRestore = nil }
            }
        }
    }

    func restoreDefaults() -> String? {
        idle.stop()
        suppressLidRetry = true
        lidError = nil
        store.update {
            $0.apps = []
            $0.manual = false
            $0.paused = false
            $0.lidEnabled = false
            $0.lidRestore = nil
        }
        guard lidSupported else { return nil }
        if commands.sleepDisabled() == 0 { return nil }
        do {
            try commands.setSleepDisabled(0)
            return nil
        } catch {
            return L10n.t("名单已清空。休眠设置没能恢复：\(error)", "The list is cleared. Sleep settings were not restored: \(error)")
        }
    }

    func allowLidRetry() {
        suppressLidRetry = false
        lidError = nil
    }

    private func syncLid(want: Bool) {
        guard lidSupported else { return }
        if want {
            if store.config.lidRestore?.active == true { return }
            if suppressLidRetry { return }
            let current = commands.sleepDisabled() ?? 0
            if current == 1 { return }
            store.update { $0.lidRestore = LidRestore(previous: current, active: true) }
            do {
                try commands.setSleepDisabled(1)
            } catch {
                store.update { $0.lidRestore = nil }
                suppressLidRetry = true
                lidError = L10n.t("合盖没改成：\(error)", "Could not change lid sleep: \(error)")
            }
        } else if store.config.lidRestore?.active == true {
            let previous = store.config.lidRestore?.previous ?? 0
            do {
                if commands.sleepDisabled() != previous {
                    try commands.setSleepDisabled(previous)
                }
                store.update { $0.lidRestore = nil }
                lidError = nil
            } catch {
                lidError = L10n.t("没能恢复原来的合盖设置：\(error)", "Could not restore the previous lid setting: \(error)")
            }
        }
    }

    private func describe(config: Config, battery: BatteryState, hold: Bool, selectedRunning: Bool) -> String {
        if let lidError { return lidError }
        if config.paused { return L10n.t("先允许睡", "Allow sleep") }
        if battery.onBattery, let percent = battery.percent, percent < config.batteryFloor {
            return L10n.t(
                "电池 \(percent)%，低于下限 \(config.batteryFloor)%，可以睡了",
                "Battery \(percent)% is below \(config.batteryFloor)%. Sleep is allowed."
            )
        }
        if hold && config.manual && !selectedRunning {
            return powerPrefix(battery) + L10n.t("现在不许睡", "Stay awake")
        }
        if hold && selectedRunning {
            return powerPrefix(battery) + L10n.t("名单里的应用还在，不许睡", "A listed app is running")
        }
        if config.lidEnabled && lidSupported && commands.sleepDisabled() == 1 && config.lidRestore?.active != true {
            return L10n.t(
                "可以睡。系统已经不许睡，退出本应用不会改动它",
                "Sleep is allowed. The system was already set to stay awake, and quitting will leave that alone."
            )
        }
        return L10n.t("可以睡", "Sleep is allowed")
    }

    private func powerPrefix(_ battery: BatteryState) -> String {
        if battery.onBattery, let percent = battery.percent {
            return L10n.t("电池 \(percent)% · ", "Battery \(percent)% · ")
        }
        return L10n.t("电源 · ", "Power · ")
    }
}

protocol PowerCommanding {
    func battery() -> BatteryState
    func sleepDisabled() -> Int?
    func setSleepDisabled(_ value: Int) throws
}

struct LivePowerCommands: PowerCommanding {
    func battery() -> BatteryState { PowerCommands.battery() }
    func sleepDisabled() -> Int? { PowerCommands.sleepDisabled() }
    func setSleepDisabled(_ value: Int) throws { try PowerCommands.setSleepDisabled(value) }
}
