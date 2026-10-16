# Open-source macOS layout tools

This workspace also contains [ScreenLayoutApp](ScreenLayoutApp/README.md), a new macOS 27 window layout app built from scratch.

This comparison separates **app window layouts** (which app window goes where) from **display arrangements** (monitor position and resolution) and **menu bar icon layouts**. These are different tasks, even when a tool calls all of them a “layout.” Features below are based on the linked project documentation, checked 16 October 2026.

| Tool | Manages | Detects display changes | Saves app window layouts | Restores automatically | Multiple named layouts | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| [SnapBack](https://github.com/jamesagarside/snapback) | App windows | Yes: dock, undock, wake | Yes, per display setup | Yes; automatic, prompt, or disabled | Yes, per display setup | Hammerspoon extension; also offers window snapping. Spaces restoration is best effort. |
| [Realign](https://github.com/hunterphillips/realign) | App windows | Yes: connect and disconnect | Yes, one per display setup | Optional; off by default | No | Native menu bar app with save and restore shortcuts. Requires macOS 14+. |
| [Monitor Glue](https://github.com/erango/monitor-glue) | App windows | Yes: reconnect, wake, unlock | Remembers positions per monitor | Yes | No named profiles documented | Continuously remembers where windows were on each monitor; requires macOS 14+. |
| [Tsubame](https://github.com/zembutsu/tsubame) | App windows | Yes: reconnect and wake | Yes, including five manual snapshot slots | Yes | Five numbered slots | Also moves windows between displays and offers keyboard nudging. Full-screen and minimized windows are excluded from manual snapshots. |
| [Rectangle](https://github.com/rxhanson/Rectangle) | App window snapping and tiling | Reacts to the current display for window commands; no display-change layout trigger documented | No saved multi-app workspaces | No | No | Free and open source; install with `brew install --cask rectangle`. Saved workspaces and display-connect triggers are features of the separate paid [Rectangle Pro](https://rectangleapp.com/pro/). |
| [Hammerspoon](https://www.hammerspoon.org/) | App windows, via Lua configuration | Yes, with [`hs.screen.watcher`](https://www.hammerspoon.org/docs/hs.screen.watcher.html) | Possible with custom configuration | Possible with custom configuration | Possible with custom configuration | [`hs.window.layout`](https://www.hammerspoon.org/docs/hs.window.layout.html) supports rules tied to a screen configuration. It is a toolkit rather than a ready-made layout saver. |
| [winlayout](https://github.com/Clustmart/winlayout) | App windows | No built-in background watcher documented | Yes, via command line | No built-in automatic restore | Yes, named saves | Simple script for manual save and restore. Saved coordinates depend on the display arrangement, so save again when it changes. |
| [displayplacer](https://github.com/jakehilborn/displayplacer) | Monitor resolution, orientation, and arrangement | No built-in automatic profile switch documented | No | No built-in automatic restore | Display configurations can be saved as commands | Use alongside a window tool if you need to restore monitor settings as well as app windows. |
| [Frost](https://github.com/frostbar/frost/) | Menu bar icons | Supports multiple displays | No | Keeps menu bar icon sections on supported macOS versions | No app window profiles | Its Layout editor arranges menu bar icons, not app windows. Requires macOS 26 or 27. |

## Which to try

- **Several workspaces for each monitor setup:** [SnapBack](https://github.com/jamesagarside/snapback).
- **One simple saved workspace per setup:** [Realign](https://github.com/hunterphillips/realign).
- **Put windows back on the same monitor without managing profiles:** [Monitor Glue](https://github.com/erango/monitor-glue).
- **Custom rules or automation:** [Hammerspoon](https://www.hammerspoon.org/).
- **Manual window snapping with an open-source app:** [Rectangle](https://github.com/rxhanson/Rectangle).
- **Restore monitor resolution and physical arrangement too:** add [displayplacer](https://github.com/jakehilborn/displayplacer).
- **Organize menu bar icons:** [Frost](https://github.com/frostbar/frost/).

Most app window tools need macOS Accessibility permission to move other apps' windows. Restore results can vary for windows that an app or macOS does not allow the Accessibility API to control. The feature comparison reflects project documentation, not hands-on testing on this Mac.
