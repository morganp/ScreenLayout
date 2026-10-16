# ScreenLayout project handoff

## Project and repository

- This repository is a fresh macOS window layout app. `ScreenLayoutApp/` is the product. The `frost/` directory is a separate, ignored reference checkout; do not treat it as the app's source.
- Root `README.md` compares other tools. `ScreenLayoutApp/README.md` documents the product. `ScreenLayoutApp/SPACES_DESIGN.md` records the multi-Space design and constraints.
- Git `main` was initialized here. Annotated tag `v0.1.0` marks the first working milestone (commit `1b2635b`). Check `git status` before editing; later features may be uncommitted or on newer commits.
- Build with `cd ScreenLayoutApp && ./build-app.sh`. The script builds, bundles, and signs `build/ScreenLayout.app` with a stable Apple Development identity. Open that bundle to run it. `.build/`, `build/`, and `frost/` are ignored.
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
- Drawers have eight positions: top left, top, top right, left, right, bottom left, bottom, bottom right. Per-monitor resting width and height are set in Drawers. A window's active frame is its grid rectangle in Layouts. After restore, Accessibility focus polling switches each drawer between resting and active frames. Some apps impose minimum window sizes; the rest position moves excess width or height off-screen so only the selected strip remains visible.
- The Focus filter requires a ScreenLayout filter to be added to each desired macOS Focus. Automatic enumeration can be blocked by macOS; the app permits manual Focus names.

## Verification and care

- Run `./build-app.sh` after Swift changes, then restart the running app to load the new executable. Verify UI changes through the app, not just compiler success.
- A Space move probe confirmed movement from Space 1 to Space 5 and back on this Mac. This does not prove every app's windows can be moved.
- The user confirmed the first left/right drawer behavior worked, though focus response felt slightly slow. A temporary-window test confirmed its resting strip; automated UI clicks did not make that app frontmost. The newer eight-position and custom-active-frame behavior builds and its settings UI was checked, but needs a normal click test on each edge/corner position.
- Preserve existing layouts and Focus assignments. Testing with a disposable layout is safer than restoring or editing the user's saved layouts.
