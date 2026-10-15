import AppKit
import Foundation

enum Catalog {
    static func load() -> [ManagedApp] {
        var byPath: [String: ManagedApp] = [:]
        for root in roots() {
            collect(root, depth: 0, into: &byPath)
        }
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, let url = app.bundleURL else { continue }
            let path = url.path
            if isSelf(path) || byPath[path] != nil { continue }
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            byPath[path] = ManagedApp(name: name, path: path)
        }
        return byPath.values
            .filter { !isSelf($0.path) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func ownBundlePath() -> String {
        Bundle.main.bundleURL.standardizedFileURL.path
    }

    static func isSelf(_ path: String) -> Bool {
        let own = ownBundlePath()
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        return standard == own || standard.hasPrefix(own + "/")
    }

    static func runningPaths() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular else { return nil }
            return app.bundleURL?.path
        })
    }

    private static func roots() -> [URL] {
        var urls = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        urls.append(homeApps)
        return urls
    }

    private static func collect(_ directory: URL, depth: Int, into apps: inout [String: ManagedApp]) {
        guard depth < 2 else { return }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in children {
            if url.pathExtension == "app" {
                let path = url.path
                if isSelf(path) { continue }
                let name = displayName(for: url)
                apps[path] = ManagedApp(name: name, path: path)
            } else if depth == 0, url.lastPathComponent == "Utilities" {
                collect(url, depth: 1, into: &apps)
            }
        }
    }

    private static func displayName(for url: URL) -> String {
        let bundle = Bundle(url: url)
        if let display = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !display.isEmpty {
            return display
        }
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
