import AppKit

struct DisplayInfo {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    /// Global coordinates with a top-left origin (same space as Accessibility positions).
    let frame: CGRect
}

enum Displays {
    static func current() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let uuid = uuid(for: id) else { return nil }
            return DisplayInfo(id: id, uuid: uuid, name: screen.localizedName, frame: CGDisplayBounds(id))
        }
    }

    static func uuid(for id: CGDirectDisplayID) -> String? {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, ref) as String
    }

    /// Identifies a docking setup by the exact set of connected monitors.
    static func profileKey(_ displays: [DisplayInfo]) -> String {
        displays.map(\.uuid).sorted().joined(separator: ",")
    }

    static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) }
    }
}
