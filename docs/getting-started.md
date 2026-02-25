# Getting Started

## Installation

### Homebrew (Recommended)

```sh
brew tap m96-chan/homebrew-tap
brew install --cask --no-quarantine ktapple
```

### Manual

1. Download the `.dmg` from [Releases](https://github.com/m96-chan/KTApple/releases)
2. Drag `KTApple.app` into `/Applications`
3. Remove the quarantine attribute (required for ad-hoc signed apps):
   ```sh
   xattr -cr /Applications/KTApple.app
   ```

### Build from Source

```sh
git clone https://github.com/m96-chan/KTApple.git
cd KTApple
swift build -c release
./scripts/bundle-app.sh
cp -R build/KTApple.app /Applications/
```

## First Launch

1. Open `KTApple.app`. A menu bar icon appears in the top-right corner.
2. macOS will prompt for **Accessibility permission**. Grant it in:
   **System Settings > Privacy & Security > Accessibility**
3. KTApple will restart automatically once permission is granted.

## Basic Workflow

### 1. Create a Tile Layout

Press `⌃⌥T` (Control + Option + T) to open the **Tile Editor**.

- Click `H` to split a tile horizontally
- Click `V` to split a tile vertically
- Click `✕` to delete a tile
- Drag tile boundaries to resize
- Click anywhere on a tile (not on a button) to apply and close

Layouts are saved automatically per display and per virtual desktop (Space).

### 2. Place Windows into Tiles

**Shift + Drag**: Hold Shift while dragging a window's title bar. A highlight overlay appears over the tile under the cursor. Release to snap the window into that tile.

### 3. Navigate with Keyboard

| Shortcut | Action |
|---|---|
| `⌃⌥←→↑↓` | Move focus to adjacent tile |
| `⌃⌥⇧←→↑↓` | Move the focused window to an adjacent tile |
| `⌃⌥=` / `⌃⌥-` | Expand / shrink the focused tile |
| `⌃⌥F` | Toggle floating (remove window from tile) |
| `⌃⌥M` | Toggle maximize (full screen, preserving tile assignment) |

### 4. Resize Gaps

Drag the boundary between two tiled windows to resize them simultaneously.

Gap size can be adjusted in **Preferences** (right-click the menu bar icon > Preferences). Changes apply immediately to all windows.

## Multi-Monitor

KTApple manages each display independently. The tile editor opens on all connected displays simultaneously. Shift + Drag works across monitors -- drag a window to a tile on any screen.

## Virtual Desktops (Spaces)

Each macOS Space has its own tile layout. Switching Spaces automatically swaps to the layout for that Space. Layouts are persisted per display per Space.

## Uninstall

### Homebrew

```sh
brew uninstall --cask ktapple
```

### Manual

```sh
rm -rf /Applications/KTApple.app
rm -rf ~/Library/Application\ Support/KTApple
defaults delete com.m96chan.KTApple
```
