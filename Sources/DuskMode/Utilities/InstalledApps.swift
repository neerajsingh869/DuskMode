import Foundation
import DuskModeCore

/// Finds installed colour-critical apps (see `ColorCriticalApps`) by reading the
/// Info.plist of every .app in the usual Applications folders. Two levels deep, because
/// Adobe installs each app inside its own folder ("Adobe Photoshop 2025/…app").
/// Public FileManager/Bundle APIs only (rule #2). Call off the main thread.
enum InstalledApps {
    static func colorCritical() -> [String: String] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"),
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [String: String] = [:]

        func inspect(_ url: URL, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { return }
            for item in items {
                if item.pathExtension == "app" {
                    if let id = Bundle(url: item)?.bundleIdentifier, ColorCriticalApps.matches(id) {
                        found[id] = item.deletingPathExtension().lastPathComponent
                    }
                } else if depth > 0,
                          (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    inspect(item, depth: depth - 1)
                }
            }
        }
        roots.forEach { inspect($0, depth: 1) }
        return found
    }
}
