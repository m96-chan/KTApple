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

    private func makeHandler() -> (DragDropHandler, MockEventProvider, MockOverlayProvider, MockDragDropDelegate, TileManager) {
        let eventProvider = MockEventProvider()
        let overlayProvider = MockOverlayProvider()
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: 0)
        let handler = DragDropHandler(eventProvider: eventProvider, overlayProvider: overlayProvider, tileManager: manager)
        let delegate = MockDragDropDelegate()
        handler.delegate = delegate
        return (handler, eventProvider, overlayProvider, delegate, manager)
    }

    // MARK: - Init

    @Test func initState() {
        let (handler, _, _, _, _) = makeHandler()
        #expect(!handler.isDragging)
        #expect(handler.highlightedTileID == nil)
        #expect(handler.draggedWindowID == nil)
    }

    // MARK: - Shift Detection

    @Test func shiftDragBeginsDrag() {
        let (handler, _, _, _, _) = makeHandler()
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
        let (handler, _, _, _, _) = makeHandler()
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .began,
            modifiers: [],
            windowID: 42
        ))

        #expect(!handler.isDragging)
    }

    @Test func dragWithoutWindowIDDoesNotBegin() {
        let (handler, _, _, _, _) = makeHandler()
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
        let (handler, _, overlay, _, manager) = makeHandler()
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
        let (handler, _, overlay, _, manager) = makeHandler()
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
        let (handler, _, overlay, _, _) = makeHandler()

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
        let (handler, _, overlay, _, _) = makeHandler()

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
        let (handler, _, _, delegate, manager) = makeHandler()
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
        let (handler, _, _, delegate, _) = makeHandler()

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
        let (handler, _, _, _, _) = makeHandler()

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
        let (handler, _, _, delegate, _) = makeHandler()
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
        let (handler, event, _, _, _) = makeHandler()
        handler.startMonitoring()
        #expect(event.isMonitoring)
    }

    @Test func stopMonitoringDeactivatesProvider() {
        let (handler, event, _, _, _) = makeHandler()
        handler.startMonitoring()
        handler.stopMonitoring()
        #expect(!event.isMonitoring)
    }

    // MARK: - Drag From Tile (no Shift)

    @Test func normalDragNotifiesUntile() {
        let (handler, _, _, delegate, _) = makeHandler()
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
        let (handler, _, _, delegate, _) = makeHandler()
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

    @Test func endWithoutDragIsIgnored() {
        let (handler, _, _, delegate, _) = makeHandler()
        handler.handleMouseEvent(MouseEvent(
            location: CGPoint(x: 500, y: 500),
            phase: .ended,
            modifiers: .shift,
            windowID: 42
        ))

        #expect(delegate.droppedWindowID == nil)
        #expect(delegate.cancelCount == 0)
    }
}
