import KTAppleCore
import SwiftUI

/// Main editor view: fullscreen dark overlay with canvas and bottom toolbar.
struct TileEditorView: View {
    @ObservedObject var viewModel: TileEditorViewModel
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Semi-transparent background — click to apply & close
            Color.black.opacity(0.7)
                .onTapGesture {
                    if viewModel.isDirty { viewModel.apply() }
                    onDismiss()
                }

            VStack(spacing: 0) {
                TileCanvasView(viewModel: viewModel) {
                    if viewModel.isDirty { viewModel.apply() }
                    onDismiss()
                }
                .padding(32)

                toolbar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand {
            viewModel.cancel()
            onDismiss()
        }
    }

    private var toolbar: some View {
        HStack {
            LayoutPresetPicker(viewModel: viewModel)

            Spacer()

            Button("Cancel") {
                viewModel.cancel()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply") {
                viewModel.apply()
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.isDirty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
