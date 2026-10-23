# Multi-Space layouts

## Current behavior

The editor canvas represents one physical display and one saved Space slot at a time. Capture creates a slot for every existing desktop Space on each connected display and records the Space of each window. Accessibility supplies windows on active Spaces; with Screen Recording permission, WindowServer information fills in windows that Accessibility omits on inactive Spaces. It excludes Finder's desktop surface. Desktop slots are matched in order to the desktop Spaces already present on each display. `Restore this layout` moves matched accessible windows to those Spaces, verifies each assignment, then applies its saved frame. A window captured from WindowServer may be skipped until Accessibility exposes it. The app does not create Spaces or enter full screen.

## Layout model

Each saved layout should contain an ordered list of **Space slots** for every connected display. A slot is either a normal desktop or a dedicated full-screen app. Each window placement refers to one slot. Normal slots may contain overlapping placements; a full-screen slot contains one primary app window. The list order is the intended Mission Control order. The required normal-space count is the number of normal slots for that display.

Older layouts migrate to one normal slot per display. The slot is initially called “Current Space” because the old data does not identify which macOS Space held each window.

## Editor

- Select a display, then a Space slot before editing its grid.
- Add, remove, rename, and reorder slots. Removing a slot requires choosing where its placements go.
- Move a placement to another slot on the same display or to a slot on another display.
- Mark an app window full screen, which gives it a dedicated slot in the desired order.
- Show the number of normal slots, detected count, and any gap before applying.

## Applying a layout

1. Match the saved display set and the currently connected displays.
2. Check Space capabilities and count the current normal Spaces on each display.
3. Stop if there are fewer existing desktop Spaces than saved desktop slots. Do not create or delete Spaces.
4. Match each saved slot to a current Space in order, then move its windows.
5. Enter full screen for dedicated slots and verify that macOS created their Spaces. Recheck the order because full-screen transitions can reorder Mission Control.
6. Move and resize ordinary windows, then report moved, skipped, and unsupported operations separately.

The operation must stop before moving windows if the Space count or mapping cannot be verified. It must never claim that a multi-Space layout was restored when only window geometry was applied.

## macOS constraints

Apple's public AppKit APIs expose whether displays have separate Spaces and let an app control *its own* full-screen windows. They do not provide a documented general API to enumerate, create, reorder, or assign other apps' windows to Spaces. Accessibility can manipulate exposed window controls, but support varies by app.

Mission Control UI automation can work with System Integrity Protection enabled, but depends on the exact macOS UI and must be checked after each step. Private window-server APIs are version dependent; yabai reports that its Space operations are broken on macOS 27 even after a workaround for its window management code. Its documented create, destroy, and reorder commands otherwise require a partially disabled System Integrity Protection setup.

Sources: [Apple Spaces setting](https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces), [Apple full-screen window behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenprimary), [yabai command reference](https://github.com/asmvik/yabai/blob/master/doc/yabai.asciidoc), [macOS 27 yabai issue](https://github.com/asmvik/yabai/issues/2800).
