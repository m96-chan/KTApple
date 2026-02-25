import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

// MARK: - Mocks

final class MockCursorProvider: CursorProvider {
    var currentCursor: CursorStyle = .arrow
    var cursorChanges: [CursorStyle] = []

    func setCursor(_ style: CursorStyle) {
        currentCursor = style
        cursorChanges.append(style)
    }
}

final class MockGapResizeDelegate: GapResizeDelegate {
    var resizedBoundaries: [TileBoundary] = []
    var affectedTileIDs: [[UUID]] = []

    func didResize(_ boundary: TileBoundary, affectedTiles: [UUID]) {
        resizedBoundaries.append(boundary)
        affectedTileIDs.append(affectedTiles)
    }
}

@Suite("GapResizeHandler")
struct GapResizeHandlerTests {
    let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeHandler(gap: CGFloat = 0) -> (GapResizeHandler, MockEventProvider, MockCursorProvider, MockGapResizeDelegate, TileManager) {
        let eventProvider = MockEventProvider()
        let cursorProvider = MockCursorProvider()
        let manager = TileManager(displayID: 1, screenFrame: screenFrame, gap: gap)
        let handler = GapResizeHandler(
            eventProvider: eventProvider,
            cursorProvider: cursorProvider,
            tileManagerResolver: { point in
                manager.screenFrame.contains(point) ? manager : nil
            }
        )
        let delegate = MockGapResizeDelegate()
        handler.delegate = delegate
        return (handler, eventProvider, cursorProvider, delegate, manager)
    }

    // MARK: - Boundary Detection

    @Test func boundariesForHorizontalSplit() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        let boundaries = handler.tileBoundaries(from: [manager])

        #expect(boundaries.count == 1)
        #expect(boundaries[0].axis == .horizontal)
    }

    @Test func boundariesForVerticalSplit() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .vertical, ratio: 0.5)

        let boundaries = handler.tileBoundaries(from: [manager])

        #expect(boundaries.count == 1)
        #expect(boundaries[0].axis == .vertical)
    }

    @Test func boundariesForThreeChildren() {
        let (handler, _, _, _, manager) = makeHandler()
        let (_, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        let third = Tile(proportion: 0.25)
        manager.root.children[1].proportion = 0.25
        manager.root.insertChild(third, at: 1)

        let boundaries = handler.tileBoundaries(from: [manager])

        #expect(boundaries.count == 2)
    }

    @Test func boundariesForNestedSplit() {
        let (handler, _, _, _, manager) = makeHandler()
        let (left, _) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)
        manager.split(left, direction: .vertical, ratio: 0.5)

        let boundaries = handler.tileBoundaries(from: [manager])

        #expect(boundaries.count == 2)
    }

    @Test func noBoundariesForLeafRoot() {
        let (handler, _, _, _, manager) = makeHandler()
        let boundaries = handler.tileBoundaries(from: [manager])
        #expect(boundaries.isEmpty)
    }

    // MARK: - Hit Testing

    @Test func boundaryAtPointFindsHorizontalBoundary() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        // Boundary should be near x=960
        let result = handler.boundaryAt(point: CGPoint(x: 960, y: 540))

        #expect(result != nil)
        #expect(result?.0.axis == .horizontal)
    }

    @Test func boundaryAtPointMissesWhenFarAway() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        let result = handler.boundaryAt(point: CGPoint(x: 100, y: 540))

        #expect(result == nil)
    }

    @Test func boundaryAtPointFindsVerticalBoundary() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .vertical, ratio: 0.5)

        // Boundary should be near y=540
        let result = handler.boundaryAt(point: CGPoint(x: 960, y: 540))

        #expect(result != nil)
        #expect(result?.0.axis == .vertical)
    }

    // MARK: - Static calculateResize

    @Test func calculateResizeBasic() {
        let result = GapResizeHandler.calculateResize(
            leadingProportion: 0.5, trailingProportion: 0.5,
            delta: 0.1, minProportion: 0.05
        )

        #expect(isApprox(result.leading, 0.6))
        #expect(isApprox(result.trailing, 0.4))
    }

    @Test func calculateResizeClampsLeading() {
        let result = GapResizeHandler.calculateResize(
            leadingProportion: 0.1, trailingProportion: 0.9,
            delta: -0.5, minProportion: 0.05
        )

        #expect(isApprox(result.leading, 0.05))
        #expect(isApprox(result.trailing, 0.95))
    }

    @Test func calculateResizeClampsTrailing() {
        let result = GapResizeHandler.calculateResize(
            leadingProportion: 0.9, trailingProportion: 0.1,
            delta: 0.5, minProportion: 0.05
        )

        #expect(isApprox(result.trailing, 0.05))
        #expect(isApprox(result.leading, 0.95))
    }

    @Test func calculateResizeZeroDelta() {
        let result = GapResizeHandler.calculateResize(
            leadingProportion: 0.5, trailingProportion: 0.5,
            delta: 0, minProportion: 0.05
        )

        #expect(isApprox(result.leading, 0.5))
        #expect(isApprox(result.trailing, 0.5))
    }

    // MARK: - Cursor Hover

    @Test func hoverOverBoundaryChangesCursorHorizontal() {
        let (handler, _, cursor, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .moved))

        #expect(cursor.currentCursor == .resizeHorizontal)
    }

    @Test func hoverOverBoundaryChangesCursorVertical() {
        let (handler, _, cursor, _, manager) = makeHandler()
        manager.split(manager.root, direction: .vertical, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .moved))

        #expect(cursor.currentCursor == .resizeVertical)
    }

    @Test func hoverAwayFromBoundaryResetsArrow() {
        let (handler, _, cursor, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .moved))
        #expect(cursor.currentCursor == .resizeHorizontal)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 100, y: 540), phase: .moved))
        #expect(cursor.currentCursor == .arrow)
    }

    @Test func hoverDoesNotChangeCursorDuringResize() {
        let (handler, _, cursor, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        // Start resize
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .began))
        cursor.cursorChanges.removeAll()

        // Move events during resize should not change cursor via hover
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 100, y: 540), phase: .moved))
        #expect(!cursor.cursorChanges.contains(.arrow))
    }

    // MARK: - Resize Drag

    @Test func dragStartsBoundaryResize() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .began))

        #expect(handler.isResizing)
        #expect(handler.activeBoundary != nil)
    }

    @Test func dragAwayFromBoundaryDoesNotResize() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 100, y: 540), phase: .began))

        #expect(!handler.isResizing)
    }

    @Test func dragEndClearsState() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .began))
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .ended))

        #expect(!handler.isResizing)
        #expect(handler.activeBoundary == nil)
    }

    @Test func dragEndNotifiesDelegate() {
        let (handler, _, _, delegate, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .began))
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .ended))

        #expect(delegate.resizedBoundaries.count == 1)
        #expect(delegate.affectedTileIDs[0].count == 2)
    }

    // MARK: - Drag Movement

    @Test func dragMovementResizesTiles() {
        let (handler, _, _, _, manager) = makeHandler()
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        let originalLeft = left.proportion
        let originalRight = right.proportion

        // Start drag at boundary
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .began))
        // Drag 192px right (10% of 1920)
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960 + 192, y: 540), phase: .changed))

        #expect(left.proportion > originalLeft)
        #expect(right.proportion < originalRight)
    }

    @Test func dragRespectMinProportion() {
        let (handler, _, _, _, manager) = makeHandler()
        let (left, right) = manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .began))
        // Drag far right to try to squish the right tile
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 1900, y: 540), phase: .changed))

        #expect(right.proportion >= TileManager.minProportion)
        #expect(left.proportion <= 1.0 - TileManager.minProportion)
    }

    @Test func dragVerticalBoundary() {
        let (handler, _, _, _, manager) = makeHandler()
        let (top, bottom) = manager.split(manager.root, direction: .vertical, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .began))
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 648), phase: .changed))

        #expect(top.proportion > 0.5)
        #expect(bottom.proportion < 0.5)
    }

    @Test func stopMonitoringEndsResize() {
        let (handler, _, _, _, manager) = makeHandler()
        manager.split(manager.root, direction: .horizontal, ratio: 0.5)

        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 960, y: 540), phase: .began))
        handler.stopMonitoring()

        #expect(!handler.isResizing)
        #expect(handler.activeBoundary == nil)
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

    // MARK: - Multi-Display

    @Test func resolverRoutesToCorrectDisplayForResize() {
        let eventProvider = MockEventProvider()
        let cursorProvider = MockCursorProvider()
        let manager1 = TileManager(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), gap: 0)
        let manager2 = TileManager(displayID: 2, screenFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), gap: 0)
        let managers = [manager1, manager2]

        let handler = GapResizeHandler(
            eventProvider: eventProvider,
            cursorProvider: cursorProvider,
            tileManagerResolver: { point in
                managers.first { $0.screenFrame.contains(point) }
            }
        )
        let delegate = MockGapResizeDelegate()
        handler.delegate = delegate

        manager2.split(manager2.root, direction: .horizontal, ratio: 0.5)

        // Boundary on display 2 should be at x=1920+960=2880
        handler.handleMouseEvent(MouseEvent(location: CGPoint(x: 2880, y: 540), phase: .began))

        #expect(handler.isResizing)
        #expect(handler.activeBoundary?.axis == .horizontal)
    }

    // MARK: - Helpers

    private func isApprox(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.01) -> Bool {
        abs(a - b) < tolerance
    }
}
