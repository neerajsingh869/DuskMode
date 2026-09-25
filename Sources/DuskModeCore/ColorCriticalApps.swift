import Foundation

/// Apps where colour accuracy is the whole job (design, photo, video). DuskMode adds
/// any of these it finds installed to the pause list automatically, once each, so a
/// fresh install never tints Figma or Photoshop (Neeraj, 2026-09-25; REGRESSIONS #23).
/// Pure logic — the app target does the disk scan and the preference writes.
public enum ColorCriticalApps {
    /// Exact bundle IDs, or families ending in `*` for apps whose ID carries a version
    /// (Adobe video apps, Capture One, Affinity, DaVinci Resolve).
    public static let bundleIDPatterns: [String] = [
        "com.figma.Desktop",
        "com.bohemiancoding.sketch3",
        "com.adobe.Photoshop",
        "com.adobe.illustrator",
        "com.adobe.InDesign",
        "com.adobe.LightroomClassicCC7",
        "com.adobe.mas.lightroomCC",
        "com.adobe.xd",
        "com.adobe.PremierePro*",
        "com.adobe.AfterEffects*",
        "com.seriflabs.affinity*",
        "com.pixelmatorteam.pixelmator.x",
        "com.captureone.captureone*",
        "com.phaseone.captureone*",
        "com.blackmagic-design.DaVinciResolve*",
        "com.apple.FinalCut",
        "com.apple.motionapp",
        "org.blenderfoundation.blender",
    ]

    public static func matches(_ bundleID: String) -> Bool {
        bundleIDPatterns.contains { pattern in
            pattern.hasSuffix("*") ? bundleID.hasPrefix(String(pattern.dropLast())) : bundleID == pattern
        }
    }

    /// Which installed apps (bundle ID → name) to add to the pause list now: colour-
    /// critical, not already paused, and never auto-added before — so an app the user
    /// removed with ✕ stays removed instead of coming back on every launch.
    public static func toAutoAdd(installed: [String: String],
                                 alreadyPaused: Set<String>,
                                 previouslyAutoAdded: Set<String>) -> [String: String] {
        installed.filter { id, _ in
            matches(id) && !alreadyPaused.contains(id) && !previouslyAutoAdded.contains(id)
        }
    }
}
