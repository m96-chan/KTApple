import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

// MARK: - Mocks

final class MockEventProvider: EventProvider {
    var isMonitoring = false
    var handler: ((MouseEvent) -> Void)?

    func startMonitoring(handler: @escaping (MouseEvent) -> Void) {
        isMonitoring = true
        self.handler = handler
    }

    func stopMonitoring() {
        isMonitoring = false
        handler = nil
    }

    func send(_ event: MouseEvent) {
        handler?(event)
    }
}

final class MockOverlayProvider: OverlayProvider {
    var highlightFrame: CGRect?
    var isHighlightVisible = false

    func showHighlight(frame: CGRect) {
        highlightFrame = frame
        isHighlightVisible = true
    }

    func hideHighlight() {
        highlightFrame = nil
        isHighlightVisible = false
    }
}

final class MockDragDropDelegate: DragDropDelegate {
    var droppedWindowID: UInt32?
    var droppedOnTileID: UUID?
    var cancelCount = 0
    var draggedFromTileWindowID: UInt32?
    var dragFromTileCount = 0

    func didDropWindow(_ windowID: UInt32, onTile tileID: UUID) {
        droppedWindowID = windowID
        droppedOnTileID = tileID
    }

    func didCancelDrop() {
        cancelCount += 1
    }

    func didDragWindowFromTile(_ windowID: UInt32) {
        draggedFromTileWindowID = windowID
        dragFromTileCount += 1
    }
}

@Suite("DragDropHandler")
struct DragDropHandlerTests {
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    /// Tracks window positions for testing. Keys: windowID → position.
    /// When `moved` contains a windowID, the position changes on query.
    final class MockWindowPositionTracker {
        var positions: [UInt32: CGPoint] = [:]
        var moved: Set<UInt32> = []
        private var queryCounts: [UInt32: Int] = [:]

        /// Returns a provider closure. On first call returns initial position,
        /// on subsequent calls returns shifted position if windowID is in `moved`.
        func provider() -> (UInt32) -> CGPoint? {
            return { [weak self] windowID in
                guard let self, let pos = self.positions[windowID] else { return nil }
                let count = self.queryCounts[windowID, default: 0]
                self.queryCounts[windowID] = count + 1
                if count > 0, self.moved.contains(windowID) {
                    return CGPoint(x: pos.x + 50, y: pos.y + 30)
                }
                return pos
            }
        }
    }

    private func makeHandler() -> (DragDropHandler, MockEventProvider, MockOverlayProvider, MockDragDropDelegate, TileManager, MockWindowPositionTracker) {
        let eventProvider = MockEventProvider()
        let overlayProvider = MockOverlayProvider()
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let tracker = MockWindowPositionTracker()
        let handler = DragDropHandler(
            eventProvider: eventProvider,
            overlayProvider: overlayProvider,
            tileManagerResolver: { point in
                manager.screenFrame.contains(point) ? manager : nil
            },
            windowPositionProvider: tracker.provider()
        )
        let delegate = MockDragDropDelegate()
        handler.delegate = delegate
        return (handler, eventProvider, overlayProvider, delegate, manager, tracker)
    }

    // MARK: - Init

    @Test func initState() {
        let (handler, _, _, _, _, _) = makeHandler()
        #expect(!handler.isDragging)
        #expect(handler.highlightedTileID == nil)
        #expect(handler.draggedWindowID == nil)
    }

    // MARK: - Shift Detection

    @Test func shiftDragBeginsDrag() {
        let (handler, _, _, _, _, _) = makeHandler()
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(handler.isDragging)
        #expect(handler.draggedWindowID == 42)
    }

    @Test func dragWithoutShiftDoesNotBegin() {
        let (handler, _, _, _, _, _) = makeHandler()
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: [],
            windowID: 42
        ))

        #expect(!handler.isDragging)
    }

    @Test func dragWithoutWindowIDDoesNotBegin() {
        let (handler, _, _, _, _, _) = makeHandler()
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: nil
        ))

        #expect(!handler.isDragging)
    }

    // MARK: - Highlight During Drag

    @Test func highlightShowsDuringDrag() {
        let (handler, _, overlay, _, manager, _) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(overlay.isHighlightVisible)
        #expect(handler.highlightedTileID != nil)
    }

    @Test func highlightUpdatesOnDragMove() {
        let (handler, _, overlay, _, manager, _) = makeHandler()
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 100, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))
        #expect(handler.highlightedTileID == left.id)

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 1500, y: 500),
            phase: .changed,
            modifiers: .shift,
            windowID: 42
        ))
        #expect(handler.highlightedTileID == right.id)
        #expect(overlay.isHighlightVisible)
    }

    @Test func highlightHidesOutsideScreen() {
        let (handler, _, overlay, _, _, _) = makeHandler()

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: -100, y: -100),
            phase: .changed,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(!overlay.isHighlightVisible)
        #expect(handler.highlightedTileID == nil)
    }

    @Test func highlightHidesOnDragEnd() {
        let (handler, _, overlay, _, _, _) = makeHandler()

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .ended,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(!overlay.isHighlightVisible)
        #expect(!handler.isDragging)
    }

    // MARK: - Drop Action

    @Test func dropOnTileNotifiesDelegate() {
        let (handler, _, _, delegate, manager, _) = makeHandler()
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 100, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 100, y: 500),
            phase: .ended,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(delegate.droppedWindowID == 42)
        #expect(delegate.droppedOnTileID == left.id)
    }

    @Test func dropOutsideScreenCancels() {
        let (handler, _, _, delegate, _, _) = makeHandler()

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: -100, y: -100),
            phase: .ended,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(delegate.droppedWindowID == nil)
        #expect(delegate.cancelCount == 1)
    }

    @Test func dropClearsState() {
        let (handler, _, _, _, _, _) = makeHandler()

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .ended,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(!handler.isDragging)
        #expect(handler.draggedWindowID == nil)
        #expect(handler.highlightedTileID == nil)
    }

    @Test func canceledDragClearsState() {
        let (handler, _, _, delegate, _, _) = makeHandler()
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: .shift,
            windowID: 42
        ))

        handler.stopMonitoring()

        #expect(delegate.cancelCount == 1)
        #expect(!handler.isDragging)
    }

    // MARK: - Monitoring

    @Test func startMonitoringActivatesProvider() {
        let (handler, event, _, _, _, _) = makeHandler()
        handler.startMonitoring()
        #expect(event.isMonitoring)
    }

    @Test func stopMonitoringDeactivatesProvider() {
        let (handler, event, _, _, _, _) = makeHandler()
        handler.startMonitoring()
        handler.stopMonitoring()
        #expect(!event.isMonitoring)
    }

    // MARK: - Drag From Tile (no Shift)

    @Test func normalDragNotifiesUntileWhenWindowMoved() {
        let (handler, _, _, delegate, _, tracker) = makeHandler()
        // Window 42 is at (500, 300) initially and will move
        tracker.positions[42] = CGPoint(x: 500, y: 300)
        tracker.moved.insert(42)

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: [],
            windowID: 42
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 510, y: 500),
            phase: .changed,
            modifiers: []
        ))

        #expect(delegate.draggedFromTileWindowID == 42)
        #expect(delegate.dragFromTileCount == 1)
        #expect(!handler.isDragging) // not a shift-drag
    }

    @Test func normalDragNotifiesOnlyOnce() {
        let (handler, _, _, delegate, _, tracker) = makeHandler()
        tracker.positions[42] = CGPoint(x: 500, y: 300)
        tracker.moved.insert(42)

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: [],
            windowID: 42
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 510, y: 500),
            phase: .changed,
            modifiers: []
        ))
        #expect(delegate.dragFromTileCount == 1)

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 520, y: 500),
            phase: .changed,
            modifiers: []
        ))

        // Should not notify again
        #expect(delegate.dragFromTileCount == 1)
    }

    @Test func contentDragDoesNotTriggerUntile() {
        let (handler, _, _, delegate, _, tracker) = makeHandler()
        // Window 42 is at (500, 300) and does NOT move (content drag)
        tracker.positions[42] = CGPoint(x: 500, y: 300)
        // NOT in tracker.moved → position stays the same

        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: [],
            windowID: 42
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 510, y: 500),
            phase: .changed,
            modifiers: []
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 520, y: 510),
            phase: .changed,
            modifiers: []
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 530, y: 520),
            phase: .ended,
            modifiers: []
        ))

        // Content drag should NOT trigger untile
        #expect(delegate.dragFromTileCount == 0)
        #expect(delegate.draggedFromTileWindowID == nil)
    }

    @Test func endWithoutDragIsIgnored() {
        let (handler, _, _, delegate, _, _) = makeHandler()
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .ended,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(delegate.droppedWindowID == nil)
        #expect(delegate.cancelCount == 0)
    }

    // MARK: - Multi-Display

    @Test func resolverRoutesToCorrectDisplay() {
        let eventProvider = MockEventProvider()
        let overlayProvider = MockOverlayProvider()
        let manager1 = TileManager(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), gap: 0)
        let manager2 = TileManager(displayID: 2, screenFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), gap: 0)
        let managers = [manager1, manager2]

        let handler = DragDropHandler(
            eventProvider: eventProvider,
            overlayProvider: overlayProvider,
            tileManagerResolver: { point in
                managers.first { $0.screenFrame.contains(point) }
            }
        )
        let delegate = MockDragDropDelegate()
        handler.delegate = delegate

        let (_, right2) = manager2.split(manager2.root, direction: .horizontal, ratio: 0.5)

        // Drag on display 2
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 2880, y: 500), // right half of display 2
            phase: .began,
            modifiers: .shift,
            windowID: 99
        ))
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 2880, y: 500),
            phase: .ended,
            modifiers: .shift,
            windowID: 99
        ))

        #expect(delegate.droppedWindowID == 99)
        #expect(delegate.droppedOnTileID == right2.id)
    }
}
