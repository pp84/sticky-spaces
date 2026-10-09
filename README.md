# StickySpaces

Menu bar app that puts windows back on the right monitor, Space and position when you
dock or undock.

- Every 30 seconds (and before sleep) it saves where every window is, per **monitor
  combination** (e.g. home = laptop + 3 monitors, office = laptop + one widescreen).
- When monitors change, it waits for things to settle (5 s), then restores the layout
  saved for that combination. Saving pauses during this time, so a half-broken
  arrangement can't overwrite a good layout.
- Menu: **Restore Layout** (⌘R), **Save Layout Now** (⌘S), toggle auto-restore, Launch at Login, log.

## Build / install

```sh
./build.sh           # → build/StickySpaces.app
./build.sh install   # → /Applications, then launches it
```

Needs **Accessibility** permission (System Settings › Privacy & Security › Accessibility).

## How it works / limits

macOS (14.5+) ignores private "move window to Space" calls from other apps, so restoring
works like a person would: switch to the window's Space, switch the target monitor to the
target Space (synthesized Ctrl+←/→), and drag the window across with the Accessibility API.
A window that only needs to change Space on the *same* monitor gets bounced through
another monitor first. Side effects: your Spaces slide and the mouse jumps around for a
few seconds while it restores. The mouse is put back afterwards.

- Requires the **Move left/right a space** shortcuts (Keyboard › Shortcuts › Mission Control)
  and *Automatically rearrange Spaces* off (Desktop & Dock › Mission Control).
- Same-monitor Space changes need at least two displays.
- Fullscreen windows and "All Desktops" windows are left to macOS.
- Windows are matched by window ID, falling back to "next window of the same app" when an
  app was relaunched. Restore never creates Spaces. If a monitor now has fewer, windows go
  to its last Space.

Log: `~/Library/Logs/StickySpaces.log`. Saved layouts: `~/Library/Application Support/StickySpaces/layouts.json`.
Debug: `open -W build/StickySpaces.app --args --diag dump`.

## License

MIT — see [LICENSE](LICENSE).
