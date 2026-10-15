import Darwin
import Foundation

enum PowerError: Error, CustomStringConvertible {
    case adminDenied(String)
    case unreadable

    var description: String {
        switch self {
        case .adminDenied(let detail):
            return detail.isEmpty ? "没有获得管理员确认" : detail
        case .unreadable:
            return "读不到当前睡眠设置"
        }
    }
}

enum Machine {
    static func isAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }

    static func isLaptop() -> Bool {
        let model = hardwareModel()
        if model.hasPrefix("MacBook") { return true }
        if model.hasPrefix("Macmini") || model.hasPrefix("MacPro") || model.hasPrefix("iMac") || model.hasPrefix("MacStudio") {
            return false
        }
        return PowerCommands.hasInternalBattery()
    }

    static var lidSupported: Bool { isLaptop() && !isAppleSilicon() }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }
}

final class IdleHold {
    private var process: Process?

    func set(on: Bool) {
        if on {
            if process?.isRunning == true { return }
            let next = Process()
            next.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            next.arguments = ["-i"]
            next.standardOutput = FileHandle.nullDevice
            next.standardError = FileHandle.nullDevice
            do {
                try next.run()
                process = next
            } catch {
                fputs("caffeinate failed: \(error)\n", stderr)
                process = nil
            }
        } else if let running = process {
            if running.isRunning {
                running.terminate()
            }
            process = nil
        }
    }

    var isHolding: Bool { process?.isRunning == true }

    func stop() {
        set(on: false)
    }
}

enum PowerCommands {
    static func battery() -> BatteryState {
        BatteryParse.parse(run("/usr/bin/pmset", ["-g", "batt"]))
    }

    static func hasInternalBattery() -> Bool {
        run("/usr/bin/pmset", ["-g", "batt"]).contains("InternalBattery")
    }

    static func sleepDisabled() -> Int? {
        let text = run("/usr/bin/pmset", ["-g"])
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, parts[0] == "SleepDisabled" else { continue }
            return Int(parts[1])
        }
        return nil
    }

    static func setSleepDisabled(_ value: Int) throws {
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw PowerError.adminDenied(err)
        }
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
