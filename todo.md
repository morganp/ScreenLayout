# Todo

## Phase B: background and launch at login

- [x] Shared `LayoutStore.shared` started by an app delegate, independent of any window.
- [x] Menu bar extra with status, restores, Open, Launch at login, Run in background, Quit.
- [x] Run in background preference (Dock icon hidden after the last window closes).
- [x] Launch at login via `SMAppService`, with live status and approval handling.
- [x] Log automatic restores from display and Focus changes.
- [ ] Verify at runtime: login launch detection, reopen from Dock, policy switching.

## Phase A: live snapping (implemented, needs runtime verification)

- [x] Shared `GridGeometry` for the editor canvas and the snap overlay (one grid per monitor).
- [x] Carbon hotkeys with registration errors in status and the debug log; recorder in the Snap tab.
- [x] Overlay panel, drag selection, live preview, cancel, undo and redo, gap, record snaps, menu bar actions.
- [ ] Verify at runtime: hotkeys, overlay on each display and in full-screen Spaces, live preview, undo, recording against a disposable layout.
- [ ] Per-placement shortcuts to snap a window to a saved grid rectangle.

## Deferred review items

- [ ] Debounced persist (the store writes layouts.json on every state change).
- [ ] Move Accessibility work off the main actor.
- [ ] Use `visibleFrame` so the menu bar and Dock areas are respected by the grid.
- [ ] Reset selection when the display set changes.

## Live layout setup (idea, from GridSnap)

[GridSnap](https://github.com/konieczkow/gridsnap) (MIT, macOS 14+, Divvy-style) is a good way to arrange windows live before recording them with ScreenLayout's Capture. Use it alongside today, and consider merging the idea into ScreenLayout.

What GridSnap does:
- Global shortcut shows a grid overlay; select cells and the focused window (or the one under the cursor) snaps there, with live preview and cancel.
- Presets: a saved grid region with its own global shortcut.
- Undo and redo of the last snap, configurable grid size and gap, multi-display.
- Not documented: display-change detection, auto restore, Spaces, full-screen windows.

Why merge:
- ScreenLayout already has per-monitor grids (Smart, 4x4, 8x4, 16x4, 16x9, custom), snapping, and Capture. The missing piece is placing real windows live, instead of editing rectangles on the canvas.
- Live place then Capture becomes one flow: arrange, press a shortcut, save as a layout.

Merge options to evaluate:
- [x] Hotkey overlay that reuses each monitor's saved grid settings; drag across cells to move the focused window via `WindowAccess.swift`.
- [x] "Place and record": each snap updates the active layout's placement for that window, so no separate Capture step.
- [ ] Per-placement shortcuts (like GridSnap presets) to snap a window to a saved grid rectangle.
- [x] Undo and redo of the last snap.
- [x] Gap between windows setting.
- [x] Decide: reimplement in Swift (preferred, shares grid code and Accessibility permission) vs. recommend running GridSnap separately. Check MIT licence terms before copying any code; credit if adapted.
- [ ] Try GridSnap first on a disposable layout to judge the interaction before designing ours.
