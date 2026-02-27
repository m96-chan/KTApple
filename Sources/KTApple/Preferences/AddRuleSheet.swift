import KTAppleCore
import SwiftUI

/// Sheet for creating a new auto-assignment rule.
struct AddRuleSheet: View {
    let displayIDs: [UInt32]
    let leafCounts: [UInt32: Int]
    let onAdd: (AppRule) -> Void
    let onCancel: () -> Void

    @State private var runningApps: [(name: String, bundleID: String)] = []
    @State private var selectedAppIndex: Int = 0
    @State private var selectedDisplayID: UInt32 = 0
    @State private var selectedTileIndex: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Auto-Assign Rule")
                .font(.headline)

            Form {
                Picker("Application", selection: $selectedAppIndex) {
                    ForEach(Array(runningApps.enumerated()), id: \.offset) { index, app in
                        Text("\(app.name) (\(app.bundleID))")
                            .tag(index)
                    }
                }

                Picker("Display", selection: $selectedDisplayID) {
                    ForEach(displayIDs, id: \.self) { id in
                        Text("Display \(id)").tag(id)
                    }
                }
                .onChange(of: selectedDisplayID) { _, _ in
                    selectedTileIndex = 0
                }

                Picker("Tile", selection: $selectedTileIndex) {
                    let count = leafCounts[selectedDisplayID] ?? 1
                    ForEach(0..<count, id: \.self) { index in
                        Text("Tile \(index + 1)").tag(index)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    guard selectedAppIndex < runningApps.count else { return }
                    let app = runningApps[selectedAppIndex]
                    let rule = AppRule(
                        bundleID: app.bundleID,
                        appName: app.name,
                        displayID: selectedDisplayID,
                        tileIndex: selectedTileIndex
                    )
                    onAdd(rule)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(runningApps.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 420, height: 320)
        .onAppear {
            loadRunningApps()
            if let first = displayIDs.first {
                selectedDisplayID = first
            }
        }
    }

    private func loadRunningApps() {
        let workspace = NSWorkspace.shared.runningApplications
        runningApps = workspace
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? bundleID
                return (name: name, bundleID: bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
