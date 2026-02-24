import CoreGraphics
import Foundation
import Testing
@testable import KTAppleCore

@Suite("DisplayObserver")
struct DisplayObserverTests {

    // MARK: - Helpers

    private func makeObserver() -> (DisplayObserver, MockDisplayProvider, MockDisplayObserverDelegate) {
        let provider = MockDisplayProvider()
        let delegate = MockDisplayObserverDelegate()
        let observer = DisplayObserver(provider: provider)
        observer.delegate = delegate
        return (observer, provider, delegate)
    }

    private func display(id: UInt32, x: CGFloat = 0, y: CGFloat = 0, w: CGFloat = 1920, h: CGFloat = 1080, name: String = "Display") -> DisplayInfo {
        DisplayInfo(id: id, frame: CGRect(x: x, y: y, width: w, height: h), name: name)
    }

    // MARK: - Connected Displays

    @Test func connectedDisplaysReturnsAll() {
        let (observer, provider, _) = makeObserver()
        provider.displays = [
            display(id: 1, name: "Main"),
            display(id: 2, name: "External"),
        ]

        let displays = observer.connectedDisplays()
        #expect(displays.count == 2)
        #expect(displays[0].name == "Main")
        #expect(displays[1].name == "External")
    }

    @Test func connectedDisplaysReturnsEmptyWhenNone() {
        let (observer, _, _) = makeObserver()
        #expect(observer.connectedDisplays().isEmpty)
    }

    // MARK: - Display Events

    @Test func displayConnectedNotifiesDelegate() {
        let (observer, _, delegate) = makeObserver()
        let newDisplay = display(id: 2, name: "External")

        observer.handleDisplayConnected(newDisplay)

        #expect(delegate.connectedDisplays.count == 1)
        #expect(delegate.connectedDisplays[0].id == 2)
    }

    @Test func displayDisconnectedNotifiesDelegate() {
        let (observer, _, delegate) = makeObserver()

        observer.handleDisplayDisconnected(displayID: 3)

        #expect(delegate.disconnectedDisplayIDs.count == 1)
        #expect(delegate.disconnectedDisplayIDs[0] == 3)
    }

    @Test func displayResizedNotifiesDelegate() {
        let (observer, _, delegate) = makeObserver()
        let resized = display(id: 1, w: 2560, h: 1440)

        observer.handleDisplayResized(resized)

        #expect(delegate.resizedDisplays.count == 1)
        #expect(delegate.resizedDisplays[0].frame.width == 2560)
    }

    // MARK: - Refresh

    @Test func refreshDetectsNewDisplay() {
        let (observer, provider, delegate) = makeObserver()
        provider.displays = [display(id: 1, name: "Main")]

        observer.refresh()  // initial state: [1]
        delegate.connectedDisplays = []  // reset after initial detection

        provider.displays = [
            display(id: 1, name: "Main"),
            display(id: 2, name: "External"),
        ]

        observer.refresh()  // now: [1, 2] → detect id=2 as new

        #expect(delegate.connectedDisplays.count == 1)
        #expect(delegate.connectedDisplays[0].id == 2)
    }

    @Test func refreshDetectsRemovedDisplay() {
        let (observer, provider, delegate) = makeObserver()
        provider.displays = [
            display(id: 1, name: "Main"),
            display(id: 2, name: "External"),
        ]

        observer.refresh()  // initial state: [1, 2]

        provider.displays = [display(id: 1, name: "Main")]

        observer.refresh()  // now: [1] → detect id=2 as removed

        #expect(delegate.disconnectedDisplayIDs.count == 1)
        #expect(delegate.disconnectedDisplayIDs[0] == 2)
    }

    @Test func refreshDetectsResizedDisplay() {
        let (observer, provider, delegate) = makeObserver()
        provider.displays = [display(id: 1, w: 1920, h: 1080)]

        observer.refresh()

        provider.displays = [display(id: 1, w: 2560, h: 1440)]

        observer.refresh()

        #expect(delegate.resizedDisplays.count == 1)
        #expect(delegate.resizedDisplays[0].frame.width == 2560)
    }

    @Test func refreshNoChangeNoDelegateCall() {
        let (observer, provider, delegate) = makeObserver()
        provider.displays = [display(id: 1)]

        observer.refresh()
        delegate.connectedDisplays = []  // reset after initial detection
        delegate.disconnectedDisplayIDs = []
        delegate.resizedDisplays = []

        observer.refresh()

        #expect(delegate.connectedDisplays.isEmpty)
        #expect(delegate.disconnectedDisplayIDs.isEmpty)
        #expect(delegate.resizedDisplays.isEmpty)
    }

    // MARK: - Start / Stop Observation

    @Test func startObservationCallsProvider() {
        let (observer, provider, _) = makeObserver()
        observer.startObserving()

        #expect(provider.isObserving)
    }

    @Test func stopObservationCallsProvider() {
        let (observer, provider, _) = makeObserver()
        observer.startObserving()
        observer.stopObserving()

        #expect(!provider.isObserving)
    }
}

// MARK: - Mocks

final class MockDisplayProvider: DisplayProvider {
    var displays: [DisplayInfo] = []
    var isObserving = false
    var onReconfiguration: (() -> Void)?

    func connectedDisplays() -> [DisplayInfo] {
        displays
    }

    func startObserving(callback: @escaping () -> Void) {
        isObserving = true
        onReconfiguration = callback
    }

    func stopObserving() {
        isObserving = false
        onReconfiguration = nil
    }
}

final class MockDisplayObserverDelegate: DisplayObserverDelegate {
    var connectedDisplays: [DisplayInfo] = []
    var disconnectedDisplayIDs: [UInt32] = []
    var resizedDisplays: [DisplayInfo] = []

    func displayDidConnect(_ display: DisplayInfo) {
        connectedDisplays.append(display)
    }

    func displayDidDisconnect(displayID: UInt32) {
        disconnectedDisplayIDs.append(displayID)
    }

    func displayDidResize(_ display: DisplayInfo) {
        resizedDisplays.append(display)
    }
}
