@preconcurrency import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import KTAppleCore
import os.log

/// Lazily resolved private system symbols.
///
/// KTApple depends on a handful of undocumented functions that every macOS
/// tiling window manager relies on (yabai, AeroSpace, Amethyst all use the
/// same ones). They are not part of any public SDK, so they cannot be linked
/// normally.
///
/// These used to be declared with `@_silgen_name`, which binds the symbol at
/// **load** time: if Apple ever removed one, dyld would fail to resolve it and
/// the app would not launch at all — the whole app lost to one missing
/// function. Resolving them lazily through `dlsym` instead turns that into a
/// graceful feature loss: the affected capability degrades and everything else
/// keeps working, and the reason is written to the log exactly once.
///
/// See issue #37.
enum PrivateSymbols {
    private static let log = AppLog.logger(for: "PrivateSymbols")

    // MARK: - Accessibility

    private typealias GetWindowFn = @convention(c) (
        AXUIElement, UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    private static let getWindowFn: GetWindowFn? = {
        resolve("_AXUIElementGetWindow", in: applicationServicesPath).map {
            unsafeBitCast($0, to: GetWindowFn.self)
        }
    }()

    /// Map an `AXUIElement` to its `CGWindowID`.
    ///
    /// Returns `.apiDisabled` when the symbol is unavailable, which callers
    /// already treat as "this window cannot be identified" and skip.
    @discardableResult
    static func axWindowID(
        _ element: AXUIElement,
        _ windowID: UnsafeMutablePointer<CGWindowID>
    ) -> AXError {
        guard let getWindowFn else { return .apiDisabled }
        return getWindowFn(element, windowID)
    }

    /// Whether window↔ID mapping is available on this system.
    static var supportsWindowIDMapping: Bool { getWindowFn != nil }

    // MARK: - CoreGraphics Spaces (CGS)

    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> CFArray?

    private static let mainConnectionIDFn: MainConnectionIDFn? = {
        resolve("CGSMainConnectionID", in: coreGraphicsPath).map {
            unsafeBitCast($0, to: MainConnectionIDFn.self)
        }
    }()

    private static let copyManagedDisplaySpacesFn: CopyManagedDisplaySpacesFn? = {
        resolve("CGSCopyManagedDisplaySpaces", in: coreGraphicsPath).map {
            unsafeBitCast($0, to: CopyManagedDisplaySpacesFn.self)
        }
    }()

    /// Per-display Spaces description, or `nil` when CGS is unavailable.
    ///
    /// Callers fall back to single-Space behaviour, which is correct for the
    /// many users who never create additional Spaces.
    static func managedDisplaySpaces() -> CFArray? {
        guard let mainConnectionIDFn, let copyManagedDisplaySpacesFn else { return nil }
        return copyManagedDisplaySpacesFn(mainConnectionIDFn())
    }

    /// Whether Spaces enumeration is available on this system.
    static var supportsSpaces: Bool {
        mainConnectionIDFn != nil && copyManagedDisplaySpacesFn != nil
    }

    // MARK: - Diagnostics

    /// One line per symbol, for the launch diagnostics dump.
    static func statusReport() -> [String] {
        [
            "_AXUIElementGetWindow: \(supportsWindowIDMapping ? "available" : "MISSING")",
            "CGS Spaces API: \(supportsSpaces ? "available" : "MISSING")",
        ]
    }

    // MARK: - Private

    private static let applicationServicesPath =
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
    private static let coreGraphicsPath =
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

    /// Look a symbol up in an already-loaded framework.
    ///
    /// `RTLD_NOLOAD` on the global handle first: these frameworks are always
    /// linked already, so this is a lookup rather than a load.
    private static func resolve(_ name: String, in framework: String) -> UnsafeMutableRawPointer? {
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {  // RTLD_DEFAULT
            return symbol
        }
        guard let handle = dlopen(framework, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(framework, RTLD_LAZY) else {
            log.error("could not open \(framework, privacy: .public) looking for \(name, privacy: .public)")
            return nil
        }
        guard let symbol = dlsym(handle, name) else {
            log.error("""
                private symbol \(name, privacy: .public) is unavailable on this macOS version — \
                the feature that depends on it is disabled
                """)
            return nil
        }
        return symbol
    }
}
