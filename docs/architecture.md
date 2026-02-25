# Architecture

## Package Structure

```
KTApple/
├── Sources/
│   ├── KTAppleCore/          # Platform-agnostic core (testable, no AppKit/SwiftUI)
│   │   ├── Tile/             # Tile, TileManager — tree data model
│   │   ├── Layout/           # LayoutStore, LayoutKey, LayoutPreset — JSON persistence
│   │   ├── Window/           # WindowManager, AccessibilityProvider protocol
│   │   ├── Hotkey/           # HotkeyManager, HotkeyAction, HotkeyBinding
│   │   ├── Display/          # DisplayObserver, DisplayProvider protocol
│   │   ├── DragDrop/         # DragDropHandler — Shift+drag placement
│   │   ├── GapResize/        # GapResizeHandler — boundary drag resize
│   │   ├── TileEditor/       # TileEditorViewModel — editor logic
│   │   ├── Space/            # SpaceProvider protocol — virtual desktop support
│   │   ├── Event/            # EventProvider protocol — CGEvent abstraction
│   │   └── AppCoordinator.swift  # Central orchestrator
│   └── KTApple/              # macOS app target
│       ├── Providers/        # Live implementations (AX API, Carbon, CGS)
│       ├── TileEditor/       # SwiftUI views for tile editor
│       ├── Preferences/      # Preferences window (SwiftUI)
│       ├── Extensions/       # NSScreen+DisplayID helper
│       └── AppDelegate.swift # App entry point, wiring
├── Tests/
│   └── KTAppleCoreTests/     # Swift Testing framework
├── Assets/                   # App icon (PNG + ICNS)
├── scripts/                  # bundle-app.sh (build + sign + DMG)
└── .github/workflows/        # CI (test.yml) + Release (release.yml)
```

## Design Principles

### Protocol-Based Dependency Injection

All external dependencies are abstracted behind protocols in `KTAppleCore`:

| Protocol | Responsibility | Live Implementation |
|---|---|---|
| `AccessibilityCheckProvider` | Check AX permission | `LiveAccessibilityChecker` |
| `AccessibilityProvider` | Window move/resize/focus | `LiveAccessibilityProvider` |
| `DisplayProvider` | Screen enumeration | `LiveDisplayProvider` |
| `HotkeyProvider` | Carbon hotkey registration | `LiveHotkeyProvider` |
| `StorageProvider` | File read/write | `LiveStorageProvider` |
| `EventProvider` | CGEvent monitoring | `LiveEventProvider` |
| `SpaceProvider` | Virtual desktop tracking | `LiveSpaceProvider` |
| `WindowLifecycleProvider` | Window create/destroy events | `LiveWindowLifecycleProvider` |

Tests use mock implementations, keeping tests fast and deterministic (no AX or CGEvent dependencies).

### Tile Tree Model

Tiles form a tree where each non-leaf node has a `layoutDirection` (horizontal or vertical) and children with proportional sizes summing to 1.0:

```
Root (horizontal)
├── Tile A (proportion: 0.5)
│   Window: Safari
└── Container (proportion: 0.5, vertical)
    ├── Tile B (proportion: 0.5)
    │   Window: Terminal
    └── Tile C (proportion: 0.5)
        Window: VS Code
```

Key operations:
- **split(tile, direction, ratio)** — Replace a leaf with a container + 2 children
- **remove(tile)** — Remove leaf, sibling absorbs its space
- **resize(tile, newProportion)** — Adjust proportion, siblings compensate
- **frame(for: tile)** — Compute screen CGRect from proportional tree
- **adjacentTile(to:direction:)** — Find neighbor via probe-point lookup

### AppCoordinator

Central orchestrator that owns all managers and handles all inter-component communication:

```
AppCoordinator
├── DisplayObserver      → display connect/disconnect/resize
├── HotkeyManager        → keyboard shortcut dispatch
├── WindowManager        → AX API operations
├── LayoutStore          → JSON persistence
├── SpaceProvider        → virtual desktop change detection
├── WindowLifecycleProvider → window create/destroy
└── tileManagers: [UInt32: TileManager]  → per-display tile trees
```

**Space-aware caching**: `spaceManagers: [displayID: [spaceID: TileManager]]` stores tile trees per Space. On Space switch, the active manager is swapped from cache.

### DragDropHandler

Monitors global mouse events. When Shift is held during a drag:

1. **began** — Identify dragged window via `CGWindowListCopyWindowInfo`
2. **changed** — Resolve `TileManager` for cursor position, highlight target tile via overlay
3. **ended** — Delegate calls `didDropWindow(windowID, onTile:)` to assign window

Uses a `TileManagerResolver` closure to support multi-monitor (returns the correct manager for any screen coordinate).

### GapResizeHandler

Monitors mouse events near tile boundaries:

1. **hover** — Detect proximity to boundary, change cursor to resize indicator
2. **drag** — Compute new proportions for adjacent tiles
3. **end** — Delegate calls `didResize(boundary, affectedTiles:)` to persist and reflow windows

## Build & Release

```sh
swift test                              # Run all tests
swift build -c release                  # Build release binary
./scripts/bundle-app.sh                 # Create .app bundle (ad-hoc signed)
./scripts/bundle-app.sh --dmg           # Also create DMG for distribution
```

**CI**: `test.yml` runs `swift test` on every push.

**Release**: Tag `v*` triggers `release.yml`:
1. Run tests
2. Build DMG
3. Create draft GitHub Release with DMG
4. Auto-update Homebrew tap (`m96-chan/homebrew-tap/Casks/ktapple.rb`)

## macOS Private APIs

| API | Purpose |
|---|---|
| `_AXUIElementGetWindow` | Map AXUIElement to CGWindowID |
| `CGSMainConnectionID` | Get connection for CGS Space queries |
| `CGSCopyManagedDisplaySpaces` | Enumerate Spaces per display |

These are used by all major macOS tiling WMs (yabai, AeroSpace, Amethyst). No SIP disable required.
