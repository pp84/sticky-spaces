import AppKit

struct SavedWindow: Codable {
    let wid: CGWindowID
    let bundleID: String
    let appName: String
    let displayUUID: String
    /// Index among the display's regular desktops (fullscreen spaces excluded).
    let desktopIndex: Int
    /// Frame relative to the display's top-left corner.
    let frame: CGRect
}

struct Layout: Codable {
    var name: String
    var savedAt: Date
    var windows: [SavedWindow]
    /// Desktop index visible on each display when saved, so restore can leave things as they were.
    var visibleDesktop: [String: Int]
}

/// One layout per monitor combination, persisted as JSON.
final class LayoutStore {
    private let url: URL
    private(set) var layouts: [String: Layout] = [:]

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickySpaces")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("layouts.json")
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            layouts = (try? decoder.decode([String: Layout].self, from: data)) ?? [:]
        }
    }

    subscript(key: String) -> Layout? {
        get { layouts[key] }
        set {
            layouts[key] = newValue
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(layouts).write(to: url, options: .atomic)
        }
    }

    static func capture(displays: [DisplayInfo]) -> Layout {
        let spaces = Spaces.all()
        let byUUID = Dictionary(uniqueKeysWithValues: displays.map { ($0.uuid, $0) })
        let windows: [SavedWindow] = Windows.list().compactMap { w in
            // Windows on several spaces ("All Desktops") or fullscreen spaces are left to macOS.
            guard w.spaceIDs.count == 1,
                  let (uuid, index) = Spaces.locate(w.spaceIDs[0], in: spaces),
                  let display = byUUID[uuid] else { return nil }
            return SavedWindow(
                wid: w.wid, bundleID: w.bundleID, appName: w.appName,
                displayUUID: uuid, desktopIndex: index,
                frame: w.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY))
        }
        var visible: [String: Int] = [:]
        for s in spaces {
            if let i = s.desktops.firstIndex(where: { $0.id == s.currentSpace }) { visible[s.displayUUID] = i }
        }
        return Layout(name: profileName(displays), savedAt: Date(), windows: windows, visibleDesktop: visible)
    }

    static func profileName(_ displays: [DisplayInfo]) -> String {
        let externals = displays.filter { CGDisplayIsBuiltin($0.id) == 0 }
        if externals.isEmpty { return "Laptop only" }
        let names = externals.map { $0.name.replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression) }
        let counted = Dictionary(grouping: names, by: { $0 }).map { $1.count > 1 ? "\($1.count)× \($0)" : $0 }
        return counted.sorted().joined(separator: " + ")
    }
}
