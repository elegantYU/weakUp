import Foundation

struct ManagedApp: Codable, Equatable {
    var name: String
    var path: String
}

struct LidRestore: Codable, Equatable {
    var previous: Int
    var active: Bool
}

struct Config: Codable, Equatable {
    var apps: [ManagedApp]
    var batteryFloor: Int
    var lidEnabled: Bool
    var paused: Bool
    var manual: Bool
    var lidRestore: LidRestore?

    static func fresh(lidAvailable: Bool) -> Config {
        Config(
            apps: [],
            batteryFloor: 20,
            lidEnabled: lidAvailable,
            paused: false,
            manual: false,
            lidRestore: nil
        )
    }
}

struct BatteryState: Equatable {
    var onBattery: Bool
    var percent: Int?
}

enum BatteryParse {
    static func parse(_ text: String) -> BatteryState {
        let onBattery = text.contains("Battery Power")
        let pattern = #"(\d+)%"#
        guard let match = text.range(of: pattern, options: .regularExpression) else {
            return BatteryState(onBattery: onBattery, percent: nil)
        }
        let raw = text[match].dropLast()
        return BatteryState(onBattery: onBattery, percent: Int(raw))
    }
}

enum PolicyDecision {
    static func shouldHold(config: Config, battery: BatteryState, selectedRunning: Bool) -> Bool {
        if config.paused { return false }
        if battery.onBattery, let percent = battery.percent, percent < config.batteryFloor {
            return false
        }
        return config.manual || selectedRunning
    }
}
