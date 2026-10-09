# StickySpaces

A tiny macOS menu bar app that puts your windows back where they belong when you
plug in or unplug your monitors.

## The problem

If you move a MacBook between desks, for example three monitors at home and one
widescreen at the office, every dock or undock scrambles your setup. macOS merges the
Spaces from disconnected monitors into the ones that are left, moves windows around and
shrinks them. When you plug back in, it rarely puts anything back. You end up spending
the first few minutes at your desk dragging windows between monitors and desktops.

## What StickySpaces does

It remembers a layout for **each combination of monitors** and restores it automatically.

- **Remembers.** Every 30 seconds, and just before the Mac sleeps, it records each window:
  which monitor, which desktop (Space) on that monitor, and its exact position and size.
- **Knows your setups.** Each set of connected monitors is a separate profile, identified
  by the displays' hardware IDs. Home and office are kept apart, and plugging into
  different ports doesn't matter.
- **Restores.** When monitors are connected or disconnected, it waits 5 seconds for macOS
  to finish shuffling, then moves every window back to its saved monitor, desktop and
  frame.
- **Doesn't save a mess.** Saving is paused while monitors are changing and while a restore
  is running, so a scrambled arrangement never overwrites a good one.
- **Learns new setups by itself.** There's nothing to configure. On a new combination of
  monitors it leaves things alone. Arrange your windows once and it will restore that
  arrangement from then on.

It works well with snapping tools (BetterSnap, Rectangle, Magnet, macOS's built-in
tiling). Snapped windows are ordinary windows with a saved frame, so they come back
snapped.

### Menu

| Item | |
|---|---|
| **Restore Layout** (⌘R) | Put everything back now |
| **Save Layout Now** (⌘S) | Save the current arrangement immediately |
| **Restore Automatically When Monitors Change** | On by default |
| **Launch at Login** | Start with your Mac |
| **Show Log** | See what it did and what it couldn't do |

## Install

Requires macOS 14 or later and the Xcode command line tools.

```sh
git clone https://github.com/pp84/sticky-spaces.git
cd sticky-spaces
./build.sh install     # builds, copies to /Applications and launches
```

Then:

1. Grant **Accessibility** permission when asked (System Settings › Privacy & Security ›
   Accessibility).
2. Make sure **Move left a space / Move right a space** are enabled in System Settings ›
   Keyboard › Keyboard Shortcuts › Mission Control. They're on by default.
3. Turn off **Automatically rearrange Spaces based on most recent use** in System Settings ›
   Desktop & Dock › Mission Control.
4. Tick **Launch at Login** in the menu.

`build.sh` signs the app with your first *Apple Development* certificate if you have one,
so the Accessibility permission survives rebuilds. Without one it falls back to ad-hoc
signing, which means granting permission again after each rebuild.

## How it works

Since macOS 14.5, apps can no longer move other apps' windows between Spaces through
the private window server calls that tools like yabai used. StickySpaces works
without disabling SIP by doing what a person would do:

1. Reads which Space every window is on, across all monitors, using read-only
   private calls that still work.
2. Switches the source and target monitors to the right Spaces by sending the
   Ctrl+← / Ctrl+→ shortcuts.
3. Moves the window across with the Accessibility API. A window dropped onto another
   monitor lands on that monitor's visible Space.
4. If a window only needs to change Space on the *same* monitor, it bounces it through
   another monitor first.

During a restore you'll see Spaces slide and the mouse jump around for a few seconds.
The mouse is put back where it was afterwards.

## Limitations

- **Native fullscreen and Split View** windows are left to macOS. Use tiled windows on
  normal desktops instead (any snapping tool).
- **Moving windows between Spaces on the same monitor needs a second display.** With the
  lid closed on a single external monitor, windows can't change Space.
- **It never creates Spaces.** If a monitor comes back with fewer desktops than were
  saved, the extra windows go to its last desktop.
- **Windows are matched by window ID.** If an app was relaunched, it falls back to "the
  next window of the same app", so several windows of one app may swap places.
- **Windows shown on all desktops** ("Assign To: All Desktops") are skipped.
- **Undocumented macOS APIs.** The app relies on them, so a future macOS update could
  break it. It also can't be distributed through the App Store.

## Files

| | |
|---|---|
| Saved layouts | `~/Library/Application Support/StickySpaces/layouts.json` (plain JSON, one entry per monitor combination) |
| Log | `~/Library/Logs/StickySpaces.log` |

To forget a setup, delete its entry from `layouts.json` and restart the app.

For debugging, `open -W build/StickySpaces.app --args --diag dump` writes every display,
Space and window to the log.

## License

MIT — see [LICENSE](LICENSE).
