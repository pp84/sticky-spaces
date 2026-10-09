import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--diag") {
    if !AXIsProcessTrusted() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }
    Diagnostics.run(Array(args[(i + 1)...]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
