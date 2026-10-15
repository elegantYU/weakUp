import Foundation

final class Store {
    var directory: URL
    private(set) var config: Config

    init(directory: URL, lidAvailable: Bool) {
        self.directory = directory
        self.config = Config.fresh(lidAvailable: lidAvailable)
        if let loaded = Self.read(from: directory) {
            config = loaded
        }
    }

    func update(_ body: (inout Config) -> Void) {
        body(&config)
        if config.batteryFloor < 1 { config.batteryFloor = 1 }
        if config.batteryFloor > 90 { config.batteryFloor = 90 }
        save()
    }

    func save() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        let temporary = file.appendingPathExtension("tmp")
        try? data.write(to: temporary, options: .atomic)
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.moveItem(at: temporary, to: file)
    }

    private static func read(from directory: URL) -> Config? {
        let file = directory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeepAwake", isDirectory: true)
    }
}
