import CoreGraphics
import Foundation

/// Switches the visible Space on a display by synthesizing the system
/// "Move left/right a space" shortcuts (Ctrl+←/→), which must be enabled in
/// System Settings › Keyboard › Shortcuts › Mission Control.
enum SpaceSwitcher {
    private static let leftArrow: CGKeyCode = 0x7B
    private static let rightArrow: CGKeyCode = 0x7C

    /// Makes `targetSpace` the visible Space on `display`. Returns false if it couldn't get there.
    @discardableResult
    static func show(space targetSpace: UInt64, on display: DisplayInfo) -> Bool {
        for _ in 0..<20 {
            guard let state = Spaces.all().first(where: { $0.displayUUID == display.uuid }),
                  let target = state.spaces.firstIndex(where: { $0.id == targetSpace }),
                  let current = state.spaces.firstIndex(where: { $0.id == state.currentSpace }) else { return false }
            if target == current { return true }
            focus(display)
            press(target > current ? rightArrow : leftArrow)
            waitForChange(on: display.uuid, from: state.currentSpace)
        }
        return Spaces.currentSpace(onDisplay: display.uuid) == targetSpace
    }

    /// Space shortcuts act on the display under the mouse pointer.
    static func focus(_ display: DisplayInfo) {
        let center = CGPoint(x: display.frame.midX, y: display.frame.midY)
        CGWarpMouseCursorPosition(center)
        // A synthetic move makes the window server register the new active display.
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(50_000)
    }

    private static func press(_ key: CGKeyCode) {
        let flags: CGEventFlags = [.maskControl, .maskSecondaryFn]
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func waitForChange(on uuid: String, from old: UInt64) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            usleep(50_000)
            if Spaces.currentSpace(onDisplay: uuid) != old { break }
        }
        // Let the slide animation finish before anything else touches windows.
        usleep(350_000)
    }
}
