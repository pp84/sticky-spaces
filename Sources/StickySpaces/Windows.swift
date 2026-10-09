import AppKit

struct LiveWindow {
    let wid: CGWindowID
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
    let frame: CGRect
    let spaceIDs: [UInt64]
}

enum Windows {
    /// Normal app windows on every Space (not just the visible ones).
    static func list() -> [LiveWindow] {
        let regularApps = Dictionary(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { a, _ in a })
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let wid = w[kCGWindowNumber as String] as? CGWindowID,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let app = regularApps[pid],
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width >= 100, frame.height >= 100 else { return nil }
            let spaces = Spaces.spaces(forWindow: wid)
            // Windows that belong to no Space are offscreen helpers / minimized
            guard !spaces.isEmpty else { return nil }
            return LiveWindow(
                wid: wid, pid: pid,
                bundleID: app.bundleIdentifier ?? app.localizedName ?? "?",
                appName: app.localizedName ?? "?",
                title: w[kCGWindowName as String] as? String ?? "",
                frame: frame, spaceIDs: spaces)
        }
    }

    // MARK: Accessibility

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(element, &wid) == .success && wid != 0 ? wid : nil
    }

    /// AX elements for all of an app's windows, including ones on other Spaces.
    /// kAXWindowsAttribute only returns windows on visible Spaces, so the rest are
    /// found by brute-forcing remote element tokens (same technique AltTab uses).
    static func axWindows(pid: pid_t) -> [CGWindowID: AXUIElement] {
        var result: [CGWindowID: AXUIElement] = [:]
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement] {
            for w in windows { if let id = windowID(of: w) { result[id] = w } }
        }

        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        for elementID: UInt64 in 0..<1000 {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let el = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue(),
                  stringAttribute(el, kAXSubroleAttribute) == kAXStandardWindowSubrole as String,
                  let id = windowID(of: el), result[id] == nil else { continue }
            result[id] = el
        }
        return result
    }

    static func stringAttribute(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func isFullscreen(_ el: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    static func setFullscreen(_ el: AXUIElement, _ on: Bool) {
        AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, on as CFBoolean)
    }

    static func setFrame(_ el: AXUIElement, _ rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        // Size, then position, then size again: some apps clamp size to the screen
        // they're currently on before the move.
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, s) }
        if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, s) }
    }
}
