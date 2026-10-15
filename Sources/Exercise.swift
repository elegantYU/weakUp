import Foundation

enum Exercise {
    static func run() -> Int32 {
        let failures = NSMutableArray()
        func check(_ name: String, _ ok: Bool) {
            if ok {
                print("ok \(name)")
            } else {
                print("fail \(name)")
                failures.add(name)
            }
        }

        let ac = BatteryParse.parse("Now drawing from 'AC Power'\n -InternalBattery-0\t100%; charged;")
        check("ac ignores percent", ac.onBattery == false && ac.percent == 100)
        let batt = BatteryParse.parse("Now drawing from 'Battery Power'\n -InternalBattery-0\t18%; discharging;")
        check("battery percent", batt.onBattery && batt.percent == 18)

        var config = Config.fresh(lidAvailable: true)
        config.batteryFloor = 20
        config.apps = [ManagedApp(name: "Cursor", path: "/Applications/Cursor.app")]
        check("below floor releases", PolicyDecision.shouldHold(config: config, battery: batt, selectedRunning: true) == false)
        check("ac holds while running", PolicyDecision.shouldHold(config: config, battery: ac, selectedRunning: true))
        config.paused = true
        check("pause wins", PolicyDecision.shouldHold(config: config, battery: ac, selectedRunning: true) == false)
        config.paused = false
        config.manual = true
        check("manual holds without apps", PolicyDecision.shouldHold(config: config, battery: ac, selectedRunning: false))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("keepawake-exercise-\(UUID().uuidString)")
        let store = Store(directory: directory, lidAvailable: true)
        let engine = Engine(store: store, lidSupported: false, commands: LivePowerCommands())
        store.update {
            $0.manual = true
            $0.paused = false
            $0.lidEnabled = false
            $0.apps = []
        }
        let on = engine.tick(runningPaths: [])
        check("manual acquires caffeinate", on.holding && engine.idle.isHolding)
        store.update { $0.paused = true }
        let off = engine.tick(runningPaths: [])
        check("pause releases caffeinate", off.holding == false && engine.idle.isHolding == false)
        engine.stop()
        try? FileManager.default.removeItem(at: directory)

        let live = PowerCommands.sleepDisabled()
        check("can read SleepDisabled", live == 0 || live == 1)
        print("SleepDisabled=\(live.map(String.init) ?? "nil") appleSilicon=\(Machine.isAppleSilicon()) laptop=\(Machine.isLaptop()) battery=\(PowerCommands.battery())")
        return failures.count == 0 ? 0 : 1
    }
}
