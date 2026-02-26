import KTAppleCore
import SwiftUI

/// SwiftUI view for the Preferences window.
struct PreferencesView: View {
    @Binding var gapSize: Double
    @Binding var bindings: [HotkeyAction: HotkeyBinding]
    var onGapSizeChanged: (Double) -> Void
    var onBindingChanged: (HotkeyBinding) -> Void

    var body: some View {
        Form {
            Section("Appearance") {
                HStack {
                    Text("Tile Gap")
                    Slider(value: $gapSize, in: 0...24, step: 1) {
                        Text("Gap Size")
                    }
                    .onChange(of: gapSize) { _, newValue in
                        onGapSizeChanged(newValue)
                    }
                    Text("\(Int(gapSize)) px")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section("Keyboard Shortcuts") {
                shortcutRow(.openEditor, label: "Open Editor")
                Divider().padding(.vertical, 2)
                shortcutRow(.focusLeft,  label: "Focus Left")
                shortcutRow(.focusRight, label: "Focus Right")
                shortcutRow(.focusUp,    label: "Focus Up")
                shortcutRow(.focusDown,  label: "Focus Down")
                Divider().padding(.vertical, 2)
                shortcutRow(.moveLeft,   label: "Move Left")
                shortcutRow(.moveRight,  label: "Move Right")
                shortcutRow(.moveUp,     label: "Move Up")
                shortcutRow(.moveDown,   label: "Move Down")
                Divider().padding(.vertical, 2)
                shortcutRow(.expandTile,      label: "Expand")
                shortcutRow(.shrinkTile,      label: "Shrink")
                shortcutRow(.toggleFloating,  label: "Toggle Floating")
                shortcutRow(.toggleMaximize,  label: "Toggle Maximize")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 520)
    }

    @ViewBuilder
    private func shortcutRow(_ action: HotkeyAction, label: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 130, alignment: .leading)
            Spacer()
            if let binding = bindings[action] {
                ShortcutRecorderView(binding: binding, onRecorded: onBindingChanged)
                    .frame(width: 110, height: 24)
            }
        }
    }
}
