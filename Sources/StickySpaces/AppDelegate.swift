import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = LayoutStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var saveTimer: Timer?
    private var settleWork: DispatchWorkItem?
    /// False while monitors are changing or a restore is running, so a half-broken
    /// arrangement never overwrites a good saved layout.
    private var canAutoSave = true
    private var restoring = false

    private var autoRestore: Bool {
        get { UserDefaults.standard.object(forKey: "autoRestore") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoRestore") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "StickySpaces")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)

        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.autoSave() }
        Log.info("started, profile '\(LayoutStore.profileName(Displays.current()))'")
        autoSave()
    }

    // MARK: Saving

    private func autoSave() {
        guard canAutoSave, !restoring, AXIsProcessTrusted() else { return }
        save()
    }

    private func save() {
        let displays = Displays.current()
        let layout = LayoutStore.capture(displays: displays)
        guard !layout.windows.isEmpty else { return }
        store[Displays.profileKey(displays)] = layout
    }

    @objc private func willSleep() {
        autoSave()
    }

    // MARK: Monitor changes

    @objc private func screensChanged() {
        // Docks bring monitors up one at a time and macOS shuffles windows for a few
        // seconds afterwards, so wait until things have been quiet for a while.
        canAutoSave = false
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.screensSettled() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func screensSettled() {
        let displays = Displays.current()
        let key = Displays.profileKey(displays)
        Log.info("monitors settled: '\(LayoutStore.profileName(displays))' (\(displays.count) displays), saved layout: \(store[key] != nil)")
        if autoRestore, let layout = store[key] {
            restore(layout, displays: displays)
        } else {
            canAutoSave = true
        }
    }

    // MARK: Restoring

    private func restore(_ layout: Layout, displays: [DisplayInfo]) {
        guard !restoring else { return }
        guard AXIsProcessTrusted() else {
            Log.info("restore skipped: no Accessibility permission")
            canAutoSave = true
            return
        }
        restoring = true
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Restoring")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Restorer(layout: layout, displays: displays).run()
            DispatchQueue.main.async { [self] in
                restoring = false
                statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "StickySpaces")
                // Only resume saving if the monitors didn't change again mid-restore.
                if settleWork?.isCancelled ?? true || Displays.profileKey(Displays.current()) == Displays.profileKey(displays) {
                    canAutoSave = true
                }
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let displays = Displays.current()
        let key = Displays.profileKey(displays)
        let saved = store[key]

        menu.addItem(disabled("Setup: \(LayoutStore.profileName(displays))"))
        if let saved {
            let time = DateFormatter.localizedString(from: saved.savedAt, dateStyle: .none, timeStyle: .short)
            menu.addItem(disabled("\(saved.windows.count) windows saved at \(time)"))
        } else {
            menu.addItem(disabled("No layout saved yet"))
        }
        if restoring { menu.addItem(disabled("Restoring…")) }
        if !AXIsProcessTrusted() {
            menu.addItem(item("⚠️ Grant Accessibility permission…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        let restoreItem = item("Restore Layout", #selector(restoreNow), key: "r")
        restoreItem.isEnabled = saved != nil && !restoring
        menu.addItem(restoreItem)
        menu.addItem(item("Save Layout Now", #selector(saveNow), key: "s"))
        menu.addItem(.separator())

        let auto = item("Restore Automatically When Monitors Change", #selector(toggleAutoRestore))
        auto.state = autoRestore ? .on : .off
        menu.addItem(auto)
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let others = store.layouts.filter { $0.key != key }.values.sorted { $0.name < $1.name }
        if !others.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Other saved setups"))
            for l in others { menu.addItem(disabled("   \(l.name) — \(l.windows.count) windows")) }
        }

        menu.addItem(.separator())
        menu.addItem(item("Show Log", #selector(showLog)))
        menu.addItem(NSMenuItem(title: "Quit StickySpaces", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func restoreNow() {
        let displays = Displays.current()
        guard let layout = store[Displays.profileKey(displays)] else { return }
        canAutoSave = false
        restore(layout, displays: displays)
    }

    @objc private func saveNow() {
        save()
        Log.info("saved manually")
    }

    @objc private func toggleAutoRestore() {
        autoRestore.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.info("launch at login: \(error)")
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func showLog() {
        NSWorkspace.shared.open(Log.url)
    }
}
