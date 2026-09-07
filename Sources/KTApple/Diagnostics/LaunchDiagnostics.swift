import AppKit
@preconcurrency import ApplicationServices
import Darwin
import Foundation
import KTAppleCore
import MachO
import Security

/// Startup environment dump.
///
/// After a macOS upgrade the usual failure reports are "nothing happens" —
/// which of TCC reset, an invalidated signature, a binary built against a
/// stale SDK, or a vanished private symbol caused it is invisible from the
/// outside. Logging the environment once at launch turns those into a single
/// `log show` away. See issue #37.
enum LaunchDiagnostics {
    private static let log = AppLog.logger(for: "Diagnostics")

    static func logEnvironment() {
        for line in report() {
            log.info("\(line, privacy: .public)")
        }
    }

    /// The same lines the log receives, for display in a support context.
    static func report() -> [String] {
        var lines: [String] = []

        let os = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")

        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        lines.append("KTApple: \(short) (\(build))")
        lines.append("Bundle: \(Bundle.main.bundlePath)")

        if let build = machOBuildVersion() {
            lines.append("Built with: macOS \(build.sdk) SDK, deployment target \(build.minOS)")
        } else {
            lines.append("Built with: unknown (no LC_BUILD_VERSION)")
        }
        lines.append("Architecture: \(architecture())")

        if let signing = signingStatus() {
            lines.append(
                "Signature: \(signing.identifier), "
                    + (signing.adhoc ? "ad-hoc" : "identified")
                    + ", " + (signing.valid ? "valid" : "INVALID")
            )
        } else {
            lines.append("Signature: could not be read")
        }

        lines.append("Accessibility trusted: \(AXIsProcessTrusted())")
        lines.append(contentsOf: PrivateSymbols.statusReport())

        return lines
    }

    // MARK: - Private

    private struct MachOBuild {
        let minOS: String
        let sdk: String
    }

    /// Read `LC_BUILD_VERSION` out of our own Mach-O header.
    ///
    /// SwiftPM does not stamp `DTSDKName` into Info.plist the way Xcode does,
    /// so the SDK the binary was actually compiled against is only recorded in
    /// the load commands. That value is what distinguishes "needs a rebuild"
    /// from every other post-upgrade failure.
    private static func machOBuildVersion() -> MachOBuild? {
        guard let header = _dyld_get_image_header(0) else { return nil }

        let base = UnsafeRawPointer(header)
        let machHeader = base.assumingMemoryBound(to: mach_header_64.self)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)

        for _ in 0..<machHeader.pointee.ncmds {
            let command = cursor.assumingMemoryBound(to: load_command.self).pointee
            if command.cmd == UInt32(LC_BUILD_VERSION) {
                let build = cursor.assumingMemoryBound(to: build_version_command.self).pointee
                return MachOBuild(
                    minOS: packedVersion(build.minos),
                    sdk: packedVersion(build.sdk)
                )
            }
            guard command.cmdsize > 0 else { return nil }
            cursor = cursor.advanced(by: Int(command.cmdsize))
        }
        return nil
    }

    /// Mach-O packs versions as `xxxx.yy.zz` in a single 32-bit word.
    private static func packedVersion(_ value: UInt32) -> String {
        let major = value >> 16
        let minor = (value >> 8) & 0xFF
        let patch = value & 0xFF
        return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    private static func architecture() -> String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }

    private struct SigningStatus {
        let identifier: String
        let adhoc: Bool
        let valid: Bool
    }

    /// Report our own code signature.
    ///
    /// KTApple is ad-hoc signed, which Gatekeeper treats differently from a
    /// Developer ID signature and which macOS re-evaluates after an upgrade.
    private static func signingStatus() -> SigningStatus? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }

        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef
        ) == errSecSuccess,
            let signingInfo = infoRef as? [String: Any]
        else { return nil }

        let identifier = signingInfo[kSecCodeInfoIdentifier as String] as? String ?? "(unsigned)"
        let flags = signingInfo[kSecCodeInfoFlags as String] as? UInt32 ?? 0
        let valid = SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess

        return SigningStatus(
            identifier: identifier,
            adhoc: SecCodeSignatureFlags(rawValue: flags).contains(.adhoc),
            valid: valid
        )
    }
}
