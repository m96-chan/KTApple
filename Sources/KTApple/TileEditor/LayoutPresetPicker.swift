import KTAppleCore
import SwiftUI

/// Row of preset layout buttons.
struct LayoutPresetPicker: View {
    @ObservedObject var viewModel: TileEditorViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LayoutPreset.allCases, id: \.rawValue) { preset in
                Button(preset.displayName) {
                    viewModel.applyPreset(preset)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
