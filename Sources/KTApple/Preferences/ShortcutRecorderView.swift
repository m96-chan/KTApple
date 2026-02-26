import AppKit
import Carbon
import KTAppleCore
import SwiftUI

/// SwiftUI wrapper that embeds a keyboard-shortcut recorder.
///
/// Clicking the view puts it into recording mode; the next key press (with any
/// modifiers) becomes the new binding and is reported via `onRecorded`.
/// Pressing Escape cancels and restores the previous display.
struct ShortcutRecorderView: NSViewRepresentable {
    let binding: HotkeyBinding
    let onRecorded: (HotkeyBinding) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView(binding: binding)
        view.onRecorded = onRecorded
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        if !nsView.isRecording {
            nsView.currentBinding = binding
        }
        nsView.onRecorded = onRecorded
    }
}

// MARK: - RecorderNSView

final class RecorderNSView: NSView {
    var currentBinding: HotkeyBinding { didSet { needsDisplay = true } }
    var onRecorded: ((HotkeyBinding) -> Void)?
    private(set) var isRecording = false

    init(binding: HotkeyBinding) {
        self.currentBinding = binding
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        // Escape cancels without changing the binding
        if event.keyCode == 53 {
            cancelRecording()
            return
        }

        let keyCode = UInt32(event.keyCode)
        var mods: KeyModifier = []
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        if event.modifierFlags.contains(.option)  { mods.insert(.option) }
        if event.modifierFlags.contains(.shift)   { mods.insert(.shift) }
        if event.modifierFlags.contains(.command) { mods.insert(.command) }

        let newBinding = HotkeyBinding(action: currentBinding.action, keyCode: keyCode, modifiers: mods)
        finishRecording()
        onRecorded?(newBinding)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording() }
        return super.resignFirstResponder()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let bgColor: NSColor = isRecording
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15)
            : NSColor.controlBackgroundColor
        bgColor.setFill()

        let inset = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: inset, xRadius: 5, yRadius: 5)
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text = isRecording ? "Press shortcut…" : shortcutDisplay(for: currentBinding)
        let textColor: NSColor = isRecording ? .secondaryLabelColor : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: textColor,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let strSize = attrStr.size()
        let origin = CGPoint(
            x: (bounds.width - strSize.width) / 2,
            y: (bounds.height - strSize.height) / 2
        )
        attrStr.draw(at: origin)
    }

    // MARK: - Private

    private func cancelRecording() {
        isRecording = false
        needsDisplay = true
        window?.makeFirstResponder(nil)
    }

    private func finishRecording() {
        isRecording = false
        needsDisplay = true
        window?.makeFirstResponder(nil)
    }

    private func shortcutDisplay(for binding: HotkeyBinding) -> String {
        var result = ""
        if binding.modifiers.contains(.control) { result += "⌃" }
        if binding.modifiers.contains(.option)  { result += "⌥" }
        if binding.modifiers.contains(.shift)   { result += "⇧" }
        if binding.modifiers.contains(.command) { result += "⌘" }
        result += keyDisplayName(keyCode: binding.keyCode)
        return result
    }
}

// MARK: - Key name lookup

private func keyDisplayName(keyCode: UInt32) -> String {
    let special: [UInt32: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
        117: "⌦", 116: "⇞", 121: "⇟",
        115: "↖", 119: "↘",
    ]
    if let name = special[keyCode] { return name }

    guard
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
        let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return "?" }

    let cfData = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue()
    guard let bytes = CFDataGetBytePtr(cfData) else { return "?" }

    return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPtr in
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        UCKeyTranslate(
            layoutPtr,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            4,
            &actualLength,
            &chars
        )
        let scalars = chars.prefix(actualLength).compactMap { Unicode.Scalar(UInt32($0)) }
        let str = String(String.UnicodeScalarView(scalars))
        return str.isEmpty ? "?" : str.uppercased()
    }
}
