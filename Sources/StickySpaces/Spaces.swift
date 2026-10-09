import CoreGraphics
import Foundation

struct DisplaySpaces {
    let displayUUID: String
    let currentSpace: UInt64
    /// Ordered left-to-right as in Mission Control. Includes fullscreen spaces.
    let spaces: [SpaceInfo]

    /// Regular desktops only; this is what a saved space index refers to.
    var desktops: [SpaceInfo] { spaces.filter { !$0.isFullscreen } }
}

struct SpaceInfo {
    let id: UInt64
    let isFullscreen: Bool
}

enum Spaces {
    static let cid = CGSMainConnectionID()

    static func all() -> [DisplaySpaces] {
        let raw = CGSCopyManagedDisplaySpaces(cid).takeRetainedValue() as? [[String: Any]] ?? []
        let mainUUID = Displays.uuid(for: CGMainDisplayID()) ?? "Main"
        return raw.compactMap { entry in
            guard var uuid = entry["Display Identifier"] as? String else { return nil }
            if uuid == "Main" { uuid = mainUUID }
            let current = (entry["Current Space"] as? [String: Any])?["id64"] as? UInt64 ?? 0
            let spaces = (entry["Spaces"] as? [[String: Any]] ?? []).compactMap { s -> SpaceInfo? in
                guard let id = s["id64"] as? UInt64 else { return nil }
                // type 0 = user desktop, 4 = fullscreen app / split view
                return SpaceInfo(id: id, isFullscreen: (s["type"] as? Int ?? 0) == 4)
            }
            return DisplaySpaces(displayUUID: uuid, currentSpace: current, spaces: spaces)
        }
    }

    static func spaces(forWindow wid: CGWindowID) -> [UInt64] {
        // mask 7 = all spaces (current + others + fullscreen)
        CGSCopySpacesForWindows(cid, 7, [wid] as CFArray)?.takeRetainedValue() as? [UInt64] ?? []
    }

    static func currentSpace(onDisplay uuid: String) -> UInt64 {
        all().first { $0.displayUUID == uuid }?.currentSpace ?? 0
    }

    /// (display uuid, desktop index) for a space id, or nil for fullscreen/unknown spaces.
    static func locate(_ spaceID: UInt64, in all: [DisplaySpaces]) -> (String, Int)? {
        for d in all {
            if let i = d.desktops.firstIndex(where: { $0.id == spaceID }) { return (d.displayUUID, i) }
        }
        return nil
    }
}
