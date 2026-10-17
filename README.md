# ScreenLayout

A fresh native SwiftUI macOS 27 window layout app. Frost and Rectangle are reference projects only; this app has its own source and package. See [docs/alternatives.md](docs/alternatives.md) for a comparison with other tools.

## Current features

- Detects display configuration events with Core Graphics, including plug and unplug notifications.
- Reads the current normal desktop Space count per display and compares it with the number of desktop Space slots in the saved layout. This read-only count uses an undocumented SkyLight API.
- Restores desktop Space slots to existing macOS desktop Spaces in order, moving matched windows and verifying each Space assignment. It does not create Spaces. The move operation uses an undocumented SkyLight API and may vary by macOS version. Full-screen slots cannot be applied yet.
- Shows attached displays, stable display UUIDs, geometry, and a live event log in **Debug events**.
- Saves layouts by the exact set of attached displays. A layout can be assigned to several macOS Focus modes.
- Captures the current windows into a saved layout, or adds a running app manually.
- Creates blank layouts or captures the current screen as a new layout. Edits and renames save automatically; **Save as copy** makes an independent layout, and **Delete layout** asks for confirmation.
- Edits one selected window area at a time on a monitor grid. **Show all apps** reveals every placement when needed. Drag the blue area to move it or its corner handle to resize it. Placements can overlap.
- A saved window can rest in one of eight edge or corner drawers. The **Drawers** tab sets the visible resting width and height for each position on each monitor. The window's grid rectangle in **Layouts** sets its active size and position. When the window gains focus it expands to that rectangle, then returns to its drawer when focus moves elsewhere. Drawer monitoring starts when the layout is restored and uses Accessibility window controls.
- Dragging previews locally and writes the saved layout on release. Grid snapping uses a small threshold before switching positions and includes flush right and bottom positions when the window size does not match whole grid cells.
- Offers Smart, 4×4, 8×4, 16×4, 16×9, and custom grids. Smart chooses 16 columns and a row count from the monitor's aspect ratio. Snap to grid can be switched off. Each monitor remembers its grid settings; **Reset grid** returns that monitor to Smart with snapping on.
- Lists Focus names found locally or entered in the app. **Focus modes…** opens a checkbox list for assigning the selected layout to any number of modes for the attached-monitor set. **Select all** then clearing one checkbox covers an all-except-one assignment. **Duplicate** creates an independent layout copy. On a Focus filter change, restores the assigned layout for the connected monitors. It can also restore the matching layout after a display change.
- Runs from a menu bar item (status, restore selected or matching layout, open the window, Launch at login, Run in background, Quit). With **Run in background** on, closing the last window hides the Dock icon and the app keeps handling display changes, Focus changes and drawers. **Open ScreenLayout** or clicking the app again brings the window back. Automatic restores are logged in **Debug events** even with no window open.
- **Launch at login** uses `SMAppService`; its state is read from macOS each time and shown in the menu and sidebar. A login launch starts without a window.
- Live snapping: a global shortcut (default Control+Option+G, configurable in the **Snap** tab) shows a grid overlay on the display under the cursor. Drag across cells and the focused window (or the window under the cursor) follows live; release to snap, Escape or release outside to cancel. A second shortcut (default Control+Option+Z) undoes the last snap and pressing it again redoes it. An optional gap in points is applied to the live frame only. The overlay uses each monitor's grid from the Layouts editor, so the grid is one shared setting: change it in either place.
- Place and record: with **Record snaps** on, a snap updates the matching window in the selected layout (no gap). **Snap window…** and **Capture focused window into selected layout** are in the menu bar item.
- Stores layouts in `~/Library/Application Support/ScreenLayout/layouts.json`.

## Build and run

Requires Xcode 27 on macOS 27.

```sh
./build-app.sh
open build/ScreenLayout.app
```

Grant ScreenLayout **Accessibility** access in System Settings when prompted. macOS requires this to read or move other apps' windows. The display log and manual grid editor work without it.

## Launch at login

Launch at login works best when the app is installed in `/Applications`. A login item registered from `build/` points at that path, so rebuilding or moving the app can leave a stale entry; turn the toggle off and on again, or remove the old entry in **System Settings → General → Login Items**. If macOS reports that approval is needed, use **Approve in System Settings…**.

## Connect macOS Focus

Turn on **Use macOS Focus filters** in ScreenLayout. If the Mac permits reading its local Focus settings, the Focus names appear automatically. If macOS blocks that file, enter the names with **Add Focus name**. For each macOS Focus you want to automate, open **System Settings → Focus → [Focus name] → Add Filter → ScreenLayout** and enter that Focus name in **Layout profile**. With each monitor combination attached, select a saved layout, click **Focus modes…**, and check the modes that should use it. The app applies that assignment when the Focus filter selects the mode, using the current set of monitors. A Focus without a ScreenLayout filter uses the `Default` assignment. Keep ScreenLayout running to respond to Focus changes.

The build script signs the app with a stable Apple Development certificate from your keychain, or the identity in `SCREENLAYOUT_SIGNING_IDENTITY`. Rebuilding with ad hoc signatures changes the app's identity and can leave macOS showing an enabled permission while `AXIsProcessTrusted()` still returns false. If this happens after changing signing identity, switch only ScreenLayout's **Device Control and Data Access** entry off and on again in System Settings, then return to the app and click **Check Accessibility access**.

## Limits in this first version

- macOS does not expose the active Focus name or configured Focus list through a public API. ScreenLayout tries to read the list from macOS's local Focus configuration file, which is an undocumented format and may be blocked by macOS privacy controls. On this development Mac, ScreenLayout is blocked from that file, so names must be added in the app. Each Focus still needs its own ScreenLayout Focus filter to signal activation. ScreenLayout checks the filter while running; it does not currently launch itself when a Focus changes.
- A saved placement targets an already-running app window. The app does not launch missing apps or restore closed windows.
- Multiple windows with the same app and title fall back to their window-list order, which can change between sessions.
- The grid uses the full display bounds, including the menu bar and Dock areas; an app may constrain its window size or position.
- The editor still describes physical displays. It does not yet save a window's Space, create or reorder Spaces, move windows between Spaces, or put other apps into full screen. See [SPACES_DESIGN.md](SPACES_DESIGN.md).

## Credits

Live snapping is inspired by and adapts parts of [GridSnap](https://github.com/konieczkow/gridsnap) by Maciej Gajewski (MIT): the hotkey grid overlay interaction, the non-activating overlay panel, global hotkey registration, and the undo and redo toggle. Thank you to the GridSnap project. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the license text.

## License

MIT. See [LICENSE](LICENSE).
