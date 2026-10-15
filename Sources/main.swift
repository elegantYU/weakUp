import AppKit

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--exercise") {
            exit(Exercise.run())
        }
        let lidSupported = Machine.lidSupported
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["KEEP_AWAKE_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = Store.defaultDirectory()
        }
        let store = Store(directory: directory, lidAvailable: lidSupported)
        let engine = Engine(store: store, lidSupported: lidSupported)
        let delegate = AppController(store: store, engine: engine, lidSupported: lidSupported)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}
