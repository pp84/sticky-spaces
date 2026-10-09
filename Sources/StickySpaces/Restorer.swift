import AppKit

/// Puts live windows back onto the display + desktop + frame recorded in a Layout.
///
/// macOS no longer lets other processes move windows between Spaces directly, but
/// moving a window onto another display via Accessibility lands it on that display's
/// visible Space. So for each window: make its current Space visible, make the target
/// Space visible, then set its frame. Same-display Space changes bounce the window
/// through another display first.
final class Restorer {
    private let layout: Layout
    private let displays: [String: DisplayInfo]
    private var axCache: [pid_t: [CGWindowID: AXUIElement]] = [:]

    private struct Move {
        let wid: CGWindowID
        let pid: pid_t
        let app: String
        let target: DisplayInfo
        let targetSpace: UInt64
        let frame: CGRect
    }

    init(layout: Layout, displays: [DisplayInfo]) {
        self.layout = layout
        self.displays = Dictionary(uniqueKeysWithValues: displays.map { ($0.uuid, $0) })
    }

    /// Blocks while it switches Spaces; call off the main thread. Returns windows moved.
    func run() -> Int {
        let started = Date()
        let mouse = CGEvent(source: nil)?.location
        let moves = plan()
        Log.info("restore '\(layout.name)': \(moves.count) windows to move")

        // Phase 1: windows that only need a different Space on the same display go
        // somewhere else first, so every remaining move is a cross-display move.
        for m in moves where currentLocation(m.wid)?.display == m.target.uuid && currentSpace(m.wid) != m.targetSpace {
            guard let bounce = displays.values.first(where: { $0.uuid != m.target.uuid }) else {
                Log.info("  \(m.app) \(m.wid): needs a second display to change Space, skipped")
                continue
            }
            place(m, on: bounce, frame: CGRect(origin: CGPoint(x: bounce.frame.minX + 40, y: bounce.frame.minY + 40), size: m.frame.size))
        }

        // Phase 2: one target Space at a time.
        var moved = 0
        let groups = Dictionary(grouping: moves, by: { $0.targetSpace })
        for (space, group) in groups.sorted(by: { $0.key < $1.key }) {
            let target = group[0].target
            for m in group {
                guard SpaceSwitcher.show(space: space, on: target) else {
                    Log.info("  could not switch \(target.name) to space \(space)")
                    break
                }
                if place(m, on: target, frame: m.frame), currentSpace(m.wid) == space { moved += 1 }
                else { Log.info("  \(m.app) \(m.wid): ended on \(Spaces.spaces(forWindow: m.wid)), wanted \(space)") }
            }
        }

        restoreVisibleDesktops()
        if let mouse { CGWarpMouseCursorPosition(mouse) }
        Log.info("restore done: \(moved)/\(moves.count) in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        return moved
    }

    // MARK: Planning

    private func plan() -> [Move] {
        let live = Windows.list()
        let spaces = Spaces.all()
        var unmatched = live
        var moves: [Move] = []

        // Match by window ID (stable while the app keeps running), then fall back to
        // the next unclaimed window of the same app (app was relaunched).
        var pairs: [(SavedWindow, LiveWindow)] = []
        var pending: [SavedWindow] = []
        for s in layout.windows {
            if let i = unmatched.firstIndex(where: { $0.wid == s.wid && $0.bundleID == s.bundleID }) {
                pairs.append((s, unmatched.remove(at: i)))
            } else {
                pending.append(s)
            }
        }
        for s in pending {
            if let i = unmatched.firstIndex(where: { $0.bundleID == s.bundleID }) { pairs.append((s, unmatched.remove(at: i))) }
        }

        for (saved, w) in pairs {
            guard let display = displays[saved.displayUUID],
                  let desktops = spaces.first(where: { $0.displayUUID == saved.displayUUID })?.desktops,
                  !desktops.isEmpty,
                  w.spaceIDs.count == 1,
                  Spaces.locate(w.spaceIDs[0], in: spaces) != nil  // leave fullscreen windows alone
            else { continue }
            let targetSpace = desktops[min(saved.desktopIndex, desktops.count - 1)].id
            let frame = saved.frame.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
            if w.spaceIDs[0] == targetSpace && w.frame.isClose(to: frame) { continue }
            moves.append(Move(wid: w.wid, pid: w.pid, app: w.appName, target: display, targetSpace: targetSpace, frame: frame))
        }
        return moves
    }

    // MARK: Moving

    /// Makes the window's current Space visible, then sets its frame onto `display`.
    @discardableResult
    private func place(_ m: Move, on display: DisplayInfo, frame: CGRect) -> Bool {
        guard let from = currentLocation(m.wid), let source = displays[from.display] else { return false }
        if source.uuid != display.uuid || from.space != m.targetSpace {
            SpaceSwitcher.show(space: from.space, on: source)
        }
        guard let ax = element(m.wid, pid: m.pid) else {
            Log.info("  \(m.app) \(m.wid): no accessibility element, skipped")
            return false
        }
        Windows.setFrame(ax, frame)
        usleep(150_000)
        return true
    }

    private func element(_ wid: CGWindowID, pid: pid_t) -> AXUIElement? {
        if let el = axCache[pid]?[wid] { return el }
        axCache[pid] = Windows.axWindows(pid: pid)
        return axCache[pid]?[wid]
    }

    private func currentSpace(_ wid: CGWindowID) -> UInt64? {
        Spaces.spaces(forWindow: wid).first
    }

    private func currentLocation(_ wid: CGWindowID) -> (display: String, space: UInt64)? {
        guard let space = currentSpace(wid),
              let display = Spaces.all().first(where: { $0.spaces.contains { $0.id == space } })?.displayUUID
        else { return nil }
        return (display, space)
    }

    private func restoreVisibleDesktops() {
        for s in Spaces.all() {
            guard let display = displays[s.displayUUID],
                  let index = layout.visibleDesktop[s.displayUUID],
                  !s.desktops.isEmpty else { continue }
            SpaceSwitcher.show(space: s.desktops[min(index, s.desktops.count - 1)].id, on: display)
        }
    }
}

private extension CGRect {
    func isClose(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 3 && abs(minY - other.minY) < 3 && abs(width - other.width) < 3 && abs(height - other.height) < 3
    }
}
