# Third-party notices

## GridSnap

ScreenLayout's live snapping (the hotkey grid overlay) adapts ideas and some code structure from [GridSnap](https://github.com/konieczkow/gridsnap), which is MIT licensed.

Adapted from GridSnap:
- The interaction model: a global shortcut shows a grid, dragging across cells selects a region, the window follows the drag as a live preview, release snaps, and Escape or releasing outside cancels.
- The non-activating `NSPanel` overlay with a `canBecomeKey` subclass.
- Carbon `RegisterEventHotKey` registration and the modifier-recording approach for shortcuts.
- Capturing the target window before the panel is shown, the focused-window or window-under-cursor rule, and the undo-then-redo toggle on a second shortcut.
- Splitting half of the gap onto each side of a snapped frame.

Not taken from GridSnap: the grid size and cell math (ScreenLayout shares each monitor's grid settings with its Layouts editor in `GridGeometry.swift`), presets, and settings UI.

GridSnap license text:

```
MIT License

Copyright (c) 2026 Maciej Gajewski

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
