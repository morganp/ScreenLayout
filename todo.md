# Todo

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
- [ ] Hotkey overlay that reuses each monitor's saved grid settings; drag across cells to move the focused window via `WindowAccess.swift`.
- [ ] "Place and record": each snap updates the active layout's placement for that window, so no separate Capture step.
- [ ] Per-placement shortcuts (like GridSnap presets) to snap a window to a saved grid rectangle.
- [ ] Undo and redo of the last snap.
- [ ] Gap between windows setting.
- [ ] Decide: reimplement in Swift (preferred, shares grid code and Accessibility permission) vs. recommend running GridSnap separately. Check MIT licence terms before copying any code; credit if adapted.
- [ ] Try GridSnap first on a disposable layout to judge the interaction before designing ours.
