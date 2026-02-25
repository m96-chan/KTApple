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
                    viewModel.selectTile(id: nil)
                    if viewModel.isDirty { viewModel.apply() }
                    onDismiss()
                }

            VStack(spacing: 0) {
                TileCanvasView(viewModel: viewModel) {
                    viewModel.selectTile(id: nil)
                    if viewModel.isDirty { viewModel.apply() }
                    onDismiss()
                }

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

            // Undo / Redo
            Button(action: { viewModel.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!viewModel.canUndo)

            Button(action: { viewModel.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!viewModel.canRedo)

            Spacer()

            // Keyboard shortcuts help
            Menu {
                Text("H — Split Horizontal")
                Text("V — Split Vertical")
                Text("⌫ — Delete Tile")
                Text("⌘Z — Undo")
                Text("⇧⌘Z — Redo")
                Text("⎋ — Cancel")
                Text("⏎ — Apply & Close")
            } label: {
                Image(systemName: "keyboard")
                    .foregroundColor(.white.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)

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
