# KTApple

**KDE Plasma KWin Tiling for macOS**

KTApple is a window manager that brings KDE Plasma's KWin Tiling to macOS.
It features a GUI-based tile layout editor and intuitive window placement via Shift + Drag.

## Highlights

Features not found in existing macOS tiling WMs (yabai, AeroSpace, Amethyst, Rectangle):

- **Visual Tile Editor** -- Add, remove, and resize tiles freely through a GUI
- **Shift + Drop Placement** -- Hold Shift while dragging a window to place it into any tile
- **Gap-Drag Resize** -- Drag the boundary between tiles to resize adjacent windows simultaneously
- **No SIP Disable Required** -- Uses only public macOS APIs (Accessibility API)

## Features

### Tile Layout Editor

| Feature | Description |
|---|---|
| Tile Splitting | Split tiles horizontally or vertically |
| Free Resize | Drag to freely adjust tile width and height |
| Tile Deletion | Remove tiles; adjacent tiles absorb the freed space |
| Layout Presets | Apply common layouts (half split, 3-column, grid, etc.) with one click |
| Relative Coordinates | Managed in normalized 0.0--1.0 coordinates, resolution-independent |

### Window Management

| Feature | Description |
|---|---|
| Shift + Drop | Hold Shift while dragging to place a window into a tile |
| Gap Drag | Drag the boundary between tiles to resize adjacent windows simultaneously |
| Floating | Supports floating windows that are not assigned to any tile |
| Auto-Float Detection | Dialogs and non-resizable windows are automatically treated as floating |
| Keyboard Shortcuts | Move, resize, and switch focus between windows via keyboard |

### Display & Workspace

| Feature | Description |
|---|---|
| Multi-Monitor | Independent tile layouts per display |
| Virtual Workspaces | Different tile layouts per desktop/workspace |
| Layout Persistence | Save and restore layouts in JSON format |

## Architecture

### Tile Tree Structure

Tiles are managed in a tree structure, following the same model as KWin.

```
RootTile (Screen)
├── Tile (Left, 60%)
│   ├── Tile (Top-Left)
│   └── Tile (Bottom-Left)
└── Tile (Right, 40%)
    ├── Tile (Top-Right)
    └── Tile (Bottom-Right)
```

Each tile node has the following properties:

- **relativeGeometry** -- Position relative to parent tile (0.0--1.0)
- **layoutDirection** -- Child tile arrangement (Horizontal / Vertical / Floating)
- **children** -- Array of child tiles (arbitrary count)
- **windows** -- References to windows assigned to the tile

### Component Structure

```
KTApple
├── TileManager         # Per-display tile tree management
├── TileEditor          # Visual tile editor (SwiftUI)
├── WindowManager       # Window operations via Accessibility API
├── HotkeyManager       # Global shortcut registration and handling
├── DragDropHandler     # Shift + Drag detection and tile snapping
├── GapResizeHandler    # Tile boundary drag-resize handling
├── LayoutStore         # JSON persistence for layouts
└── DisplayObserver     # Monitor connect/disconnect observation
```

### macOS API Strategy

| Layer | API |
|---|---|
| Window Operations | `AXUIElement` (Accessibility API) |
| Window Enumeration | `CGWindowListCopyWindowInfo` |
| Global Event Monitoring | `CGEvent` Tap / `NSEvent.addGlobalMonitorForEvents` |
| Hotkey Registration | `Carbon.HIToolbox` (RegisterEventHotKey) |
| Display Monitoring | `CGDisplayRegisterReconfigurationCallback` |
| UI | SwiftUI |

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Swift 6 / Xcode 16+**
- **Accessibility Permission** -- Must be granted in System Settings > Privacy & Security > Accessibility
- **No SIP disable required**

## Default Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌃⌥T` | Open tile editor |
| `⌃⌥←→↑↓` | Move focus to adjacent tile |
| `⌃⌥⇧←→↑↓` | Move window to adjacent tile |
| `⌃⌥F` | Toggle window floating |
| `⌃⌥M` | Toggle window maximize |
| `⌃⌥=` / `⌃⌥-` | Expand / shrink current tile |

## Comparison with Existing Tools

| Feature | KTApple | yabai | AeroSpace | Amethyst | Rectangle |
|---|---|---|---|---|---|
| Visual Tile Editor | **Yes** | No | No | No | No |
| Free Tile Placement | **Yes** | BSP only | i3 tree | Fixed layouts | Presets only |
| Shift + Drop Placement | **Yes** | Drag zones | No | No | Drag snap |
| Gap-Drag Resize | **Yes** | No | No | No | No |
| Auto-Tiling | Optional | Yes | Yes | Yes | No |
| No SIP Required | **Yes** | Partial | Yes | Yes | Yes |
| GUI Settings | **Yes** | CLI only | TOML | GUI | GUI |

## Installation

### Homebrew (planned)

```sh
brew tap m96-chan/tap
brew install --cask --no-quarantine ktapple
```

### Manual Installation

1. Download `.dmg` from [Releases](https://github.com/m96-chan/KTApple/releases)
2. Move `KTApple.app` to `/Applications`
3. Remove quarantine attribute:
   ```sh
   xattr -cr /Applications/KTApple.app
   ```
4. Grant permission in System Settings > Privacy & Security > Accessibility

> **Note**: Cannot be distributed via the Mac App Store due to Accessibility API sandbox restrictions. The app is ad-hoc signed (no Apple Developer Program). Gatekeeper bypass is required via `xattr -cr` or Homebrew's `--no-quarantine` flag.

## Distribution

- Distributed outside the Mac App Store (App Sandbox is incompatible with Accessibility API)
- Ad-hoc signed (no Developer ID / notarization)
- Homebrew tap: `m96-chan/tap` with `--no-quarantine` cask

## License

[GPL-3.0](LICENSE)
