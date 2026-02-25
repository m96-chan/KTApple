# CLAUDE.md

## Project Overview

KTApple — KDE Plasma KWin Tiling for macOS. A menu bar window manager with visual tile editor, Shift+Drop placement, and gap-drag resize.

## Architecture

- `Sources/KTAppleCore/` — Platform-agnostic core library (testable)
- `Sources/KTApple/` — macOS app target (SwiftUI, Accessibility API)
- `Tests/KTAppleCoreTests/` — Swift Testing framework
- All external dependencies (Accessibility, Display, Hotkey, Storage) are protocol-abstracted for testability

## Build & Test

```sh
swift test                    # Run all tests (macOS only)
swift build -c release        # Release build
./scripts/bundle-app.sh       # Create .app bundle
```

## Key Design Decisions

- No App Sandbox (incompatible with Accessibility API)
- Ad-hoc signing (no Apple Developer Program)
- Distribution via Homebrew tap with `--no-quarantine`
- TDD approach: all core logic has tests with protocol-based mocks

## Known Pitfalls

### SwiftUI DragGesture in ForEach — DO NOT update ViewModel during drag

**Problem**: When a `DragGesture` handler calls `objectWillChange.send()` (or sets any `@Published` property) on an `ObservableObject` that a parent view observes, the parent's `body` is re-evaluated. This re-creates `ForEach` children, and even with stable IDs, the updated `.position()` corrupts the active gesture's coordinate reference. The drag appears to "jump", "stick", or stop responding entirely.

**This bit us 10+ times on the TileEditor boundary drag.**

**Correct pattern**:
```swift
// In the drag handle view:
@GestureState private var dragTranslation: CGSize = .zero

.position(x: originalX, y: originalY)           // stays fixed
.offset(x: dragTranslation.width, ...)          // visual movement only
.gesture(
    DragGesture(coordinateSpace: .named("parent"))
        .updating($dragTranslation) { value, state, _ in
            state = value.translation               // NO ViewModel update
        }
        .onEnded { value in
            onDragEnd(finalPosition)                // update ViewModel ONCE
        }
)
```

**Rules**:
1. NEVER call `objectWillChange.send()` or set `@Published` during `.onChanged`
2. Use `@GestureState` for visual feedback during drag (auto-resets on end)
3. Apply the final state in `.onEnded` only
4. The drag handle view should NOT have `@ObservedObject` — pass data as plain values + closures

### ForEach Identity Stability

`Identifiable` structs used in `ForEach` must have **deterministic IDs** that survive re-renders. Never use `UUID()` in `init` for items that are recomputed on every render cycle. Derive IDs from stable data:
```swift
// BAD: new ID every render → ForEach destroys/recreates views
public let id = UUID()

// GOOD: stable across re-renders
public var id: String { "\(leftTileID)_\(rightTileID)" }
```

### Three-Step Resize Workaround (macOS Accessibility API)

When moving windows between displays, macOS enforces size constraints. Always:
1. `resizeWindow` → 2. `moveWindow` → 3. `resizeWindow` (same size again)

### Reinstall: must rm -rf before cp -R

`cp -R` does NOT overwrite an existing `.app` bundle reliably on macOS. Always delete first:
```sh
osascript -e 'tell application "KTApple" to quit' 2>/dev/null; sleep 1
rm -rf /Applications/KTApple.app
cp -R build/KTApple.app /Applications/KTApple.app
open /Applications/KTApple.app
```

### Tile Coordinate System

Tiles use proportional coordinates (0.0–1.0) relative to siblings, not absolute screen positions. When converting screen positions to tile proportions, always account for the parent tile's offset (use `rawFrame(for:)` to get the parent's position).
