# Keyboard Shortcuts

All shortcuts use **Control + Option** (`⌃⌥`) as the base modifier.

## Tile Editor

| Shortcut | Action |
|---|---|
| `⌃⌥T` | Toggle tile editor (open/close on all displays) |

## Focus Navigation

| Shortcut | Action |
|---|---|
| `⌃⌥←` | Focus left |
| `⌃⌥→` | Focus right |
| `⌃⌥↑` | Focus up |
| `⌃⌥↓` | Focus down |

Moves keyboard focus to the window in the adjacent tile. Works across nested tile layouts.

## Window Movement

| Shortcut | Action |
|---|---|
| `⌃⌥⇧←` | Move window left |
| `⌃⌥⇧→` | Move window right |
| `⌃⌥⇧↑` | Move window up |
| `⌃⌥⇧↓` | Move window down |

Moves the focused window into the adjacent tile and resizes it to fit.

## Tile Resize

| Shortcut | Action |
|---|---|
| `⌃⌥=` | Expand tile (+5%) |
| `⌃⌥-` | Shrink tile (-5%) |

Adjusts the focused tile's proportion relative to its siblings. All windows in affected tiles are repositioned immediately.

## Window State

| Shortcut | Action |
|---|---|
| `⌃⌥F` | Toggle floating |
| `⌃⌥M` | Toggle maximize |

- **Floating**: Removes the window from its tile. The window returns to its original size and position.
- **Maximize**: Expands the window to fill the entire screen. Press again to restore to its original tile.

## Mouse Actions

| Action | Description |
|---|---|
| **Shift + Drag** | Hold Shift while dragging a window's title bar to place it into a tile |
| **Boundary Drag** | Drag the gap between two tiled windows to resize them |

## Key Code Reference

For contributors -- the virtual key codes used in `HotkeyManager.registerDefaults()`:

| Key | macOS Virtual Key Code |
|---|---|
| T | 17 |
| F | 3 |
| M | 46 |
| = | 24 |
| - | 27 |
| Left Arrow | 123 |
| Right Arrow | 124 |
| Down Arrow | 125 |
| Up Arrow | 126 |
