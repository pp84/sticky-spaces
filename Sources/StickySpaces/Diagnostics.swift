import AppKit

/// Command-line probes, e.g. `open StickySpaces.app --args --diag dump`. Output goes to the log.
enum Diagnostics {
    static func run(_ args: [String]) {
        Log.info("diag \(args) axTrusted=\(AXIsProcessTrusted())")
        switch args.first {
        case "dump": dump()
        case "restore":
            let displays = Displays.current()
            let key = Displays.profileKey(displays)
            if args.count > 1 && args[1] == "save" { LayoutStore()[key] = LayoutStore.capture(displays: displays) }
            guard let layout = LayoutStore()[key] else { Log.info("no saved layout"); return }
            _ = Restorer(layout: layout, displays: displays).run()
        case "frame" where args.count == 6:
            let wid = CGWindowID(args[1])!
            let v = args[2...].map { CGFloat(Double($0)!) }
            guard let w = Windows.list().first(where: { $0.wid == wid }),
                  let ax = Windows.axWindows(pid: w.pid)[wid] else { Log.info("window \(wid) not found via AX"); return }
            Windows.setFrame(ax, CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))
            usleep(300_000)
            Log.info("frame \(wid): \(String(describing: Windows.list().first { $0.wid == wid }?.frame))")
        case "switch" where args.count == 3:
            let display = Displays.current()[Int(args[1])!]
            let state = Spaces.all().first { $0.displayUUID == display.uuid }!
            let i = state.spaces.firstIndex { $0.id == state.currentSpace }!
            let target = state.spaces[args[2] == "right" ? min(i + 1, state.spaces.count - 1) : max(i - 1, 0)]
            let ok = SpaceSwitcher.show(space: target.id, on: display)
            Log.info("switch \(display.name) -> space \(target.id): \(ok)")
            dumpSpaces()
        case "move" where args.count == 3:
            let wid = CGWindowID(args[1])!
            let display = Displays.current()[Int(args[2])!]
            guard let w = Windows.list().first(where: { $0.wid == wid }),
                  let ax = Windows.axWindows(pid: w.pid)[wid] else { Log.info("window \(wid) not found via AX"); return }
            Log.info("before: spaces \(Spaces.spaces(forWindow: wid)) frame \(w.frame)")
            Windows.setFrame(ax, CGRect(origin: CGPoint(x: display.frame.minX + 80, y: display.frame.minY + 80), size: w.frame.size))
            usleep(500_000)
            let after = Windows.list().first { $0.wid == wid }
            Log.info("after: spaces \(Spaces.spaces(forWindow: wid)) frame \(String(describing: after?.frame)); display current space \(Spaces.currentSpace(onDisplay: display.uuid))")
        default:
            Log.info("unknown diag command")
        }
    }

    static func dumpSpaces() {
        let displays = Displays.current()
        for s in Spaces.all() {
            let name = displays.first { $0.uuid == s.displayUUID }?.name ?? "(disconnected)"
            Log.info("  display \(name) current=\(s.currentSpace) spaces=\(s.spaces.map { $0.isFullscreen ? "\($0.id)F" : "\($0.id)" })")
        }
    }

    static func dump() {
        for (i, d) in Displays.current().enumerated() { Log.info("display[\(i)] \(d.name) \(d.uuid) \(d.frame)") }
        dumpSpaces()
        let windows = Windows.list()
        var axByPid: [pid_t: [CGWindowID: AXUIElement]] = [:]
        for w in windows where axByPid[w.pid] == nil { axByPid[w.pid] = Windows.axWindows(pid: w.pid) }
        for w in windows {
            let ax = axByPid[w.pid]?[w.wid]
            Log.info("  wid=\(w.wid) \(w.appName) '\(w.title.prefix(30))' spaces=\(w.spaceIDs) frame=\(w.frame) ax=\(ax != nil) fs=\(ax.map(Windows.isFullscreen) ?? false)")
        }
    }
}
