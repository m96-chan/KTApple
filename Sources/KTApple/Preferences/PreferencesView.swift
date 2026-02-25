import SwiftUI

/// SwiftUI view for the Preferences window.
struct PreferencesView: View {
    @Binding var gapSize: Double
    var onGapSizeChanged: (Double) -> Void

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
                VStack(alignment: .leading, spacing: 6) {
                    shortcutRow("Open Editor", "Ctrl + Opt + T")
                    shortcutRow("Focus", "Ctrl + Opt + Arrow")
                    shortcutRow("Move Window", "Ctrl + Opt + Shift + Arrow")
                    shortcutRow("Expand / Shrink", "Ctrl + Opt + = / -")
                    shortcutRow("Toggle Floating", "Ctrl + Opt + F")
                    shortcutRow("Toggle Maximize", "Ctrl + Opt + M")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
                .frame(width: 150, alignment: .leading)
            Spacer()
            Text(shortcut)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }
}
