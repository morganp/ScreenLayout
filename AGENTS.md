# ScreenLayout project handoff

## Project and repository

- This repository is a fresh macOS window layout app. The repository root is the product. The `frost/` directory is a separate, ignored reference checkout; do not treat it as the app's source.
- `README.md` documents the product. `docs/alternatives.md` compares other tools. `SPACES_DESIGN.md` records the multi-Space design and constraints.
- Git `main` was initialized here. Annotated tag `v0.1.0` marks the first working milestone (commit `1b2635b`). Check `git status` before editing; later features may be uncommitted or on newer commits.
- Build with `./build-app.sh`. The script builds, bundles, and signs `build/ScreenLayout.app` with a stable Apple Development identity. Open that bundle to run it. `.build/`, `build/`, and `frost/` are ignored.
- User data lives at `~/Library/Application Support/ScreenLayout/layouts.json`. Do not delete or rewrite it while testing; use temporary layouts and remove them afterward.

## Code map

- `Sources/ScreenLayout/Models.swift`: Codable saved layouts, window placements, Space slots, grid and drawer settings, display info.
- `LayoutStore.swift`: observable application state, persistence, display/Focus monitoring, layout editing, restore orchestration, live drawers.
- `ScreenLayoutApp.swift`: SwiftUI shell, Layouts, Drawers, Debug events, and grid canvas.
- `WindowAccess.swift`: Accessibility window discovery, geometry, and focus tracking.
- `SpaceInventory.swift` and `Sources/SpaceBridge/`: runtime SkyLight Space enumeration and window moves. These are undocumented macOS APIs; verify behavior after OS updates.
- `FocusCatalog.swift` and `LayoutFocusFilter.swift`: Focus names and the App Intents Focus filter.

## Current behavior and limits

- Displays are detected through Core Graphics callbacks and shown in the Debug events tab. Layouts are keyed by connected display set and can be assigned to Focus modes.
- The editor saves changes automatically. Capture creates a new layout. Restore applies saved windows. Grid settings are remembered per monitor.
- Multi-Space desktop slots map in order to desktop Spaces that already exist. Restore moves and verifies matched windows. It does not create Spaces. Full-screen slots are editable but cannot yet be applied.
- Drawers have eight positions: top left, top, top right, left, right, bottom left, bottom, bottom right. Resting sizes are set in Drawers by clicking or dragging on the monitor's shared grid (`GridBackdrop`, snap setting respected) and stored as unit fractions (`DrawerSize`). `Preferences.cornerRules` (per monitor, default separate) selects separate corners, top and bottom spanning, or left and right spanning; corner positions are illegal under the last two and a saved corner assignment maps to the rule's edge at runtime (logged once, saved layout untouched). Each edge has a per-monitor drawer count of 0 to 8 and each corner 0 or 1 (`Preferences.drawerCounts`; edges default 1, corners default 0; `migrateCornerDrawers` turns a corner on once if the monitor has a saved size for it or a layout window uses it, never overwriting a stored count). Count 0 disables a position: no rectangle, no reserved space, not selectable in the Layouts Window behavior picker. `LayoutStore.usableDrawerEdge` resolves a saved assignment through the corner rule, then to the nearest enabled edge, else nil (window stays normal), logged once and never rewriting the saved layout. Every enabled drawer reserves space for neighbours at its effective depth (saved size, else standard); under the separate rule a disabled corner lets top and bottom run full width and left and right sit inside an enabled top or bottom. `WindowPlacement.drawerSlot` (default 0) picks the slot; a slot beyond the count clamps to the last at runtime, logged once, saved layout untouched. Slots divide the edge's span equally; with Snap to grid on, inner boundaries snap to cell boundaries, keep at least one cell each and stay strictly increasing, and the count is capped at the cell count (`DrawerGeometry.divide`). `DrawerGeometry.rects` (`DrawerGeometry.swift`, via `LayoutStore.drawerRects`, keyed by `DrawerKey` of edge and slot; `enabling:` gives the preview rect for an off position) is the only place resting rectangles are computed; active drawers are keyed by edge, slot and window, and two windows in one slot are logged and flagged in Layouts. the Drawers canvas (all enabled strips, dashed outlines for off positions, click to select or enable), restore, `startDrawers`, `refreshRestingDrawers` and `WindowAccess.setDrawerFrame` all use it. A window's active frame is its grid rectangle in Layouts. After restore, Accessibility focus polling switches each drawer between resting and active frames. Some apps impose minimum window sizes; the rest position moves excess width or height off-screen so only the selected strip remains visible.
- The Focus filter requires a ScreenLayout filter to be added to each desired macOS Focus. Automatic enumeration can be blocked by macOS; the app permits manual Focus names.

## Verification and care

- Run `./build-app.sh` after Swift changes, then restart the running app to load the new executable. Verify UI changes through the app, not just compiler success.
- A Space move probe confirmed movement from Space 1 to Space 5 and back on this Mac. This does not prove every app's windows can be moved.
- The user confirmed the first left/right drawer behavior worked, though focus response felt slightly slow. A temporary-window test confirmed its resting strip; automated UI clicks did not make that app frontmost. The grid-based drawer editor, corner rules, multiple drawers per edge, disabled positions and the always-drawn canvas build but are unchecked at runtime; they need a normal click test on each position under each corner rule. `DrawerGeometry.rects` was checked with a throwaway program for bottom and right enabled at default depth (right ends above bottom under topBottom and separate).
- Preserve existing layouts and Focus assignments. Testing with a disposable layout is safer than restoring or editing the user's saved layouts.
