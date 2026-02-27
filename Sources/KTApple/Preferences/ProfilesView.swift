import KTAppleCore
import SwiftUI

/// Compact profile management list embedded in the Preferences form.
struct ProfilesView: View {
    @State private var profiles: [LayoutProfile]
    let onProfileRenamed: (UUID, String) -> Void
    let onProfileDeleted: (UUID) -> Void

    init(
        profiles: [LayoutProfile],
        onProfileRenamed: @escaping (UUID, String) -> Void,
        onProfileDeleted: @escaping (UUID) -> Void
    ) {
        _profiles = State(initialValue: profiles)
        self.onProfileRenamed = onProfileRenamed
        self.onProfileDeleted = onProfileDeleted
    }

    var body: some View {
        if profiles.isEmpty {
            Text("No profiles yet. Use the menu bar → Profiles → Save Current Layout as Profile…")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.vertical, 4)
        } else {
            ForEach(Array(profiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
                ProfileRow(
                    index: index,
                    profile: profile,
                    onRename: { newName in
                        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
                            profiles[i].name = newName
                        }
                        onProfileRenamed(profile.id, newName)
                    },
                    onDelete: {
                        profiles.removeAll { $0.id == profile.id }
                        onProfileDeleted(profile.id)
                    }
                )
            }
        }
    }
}

// MARK: - ProfileRow

private struct ProfileRow: View {
    let index: Int
    let profile: LayoutProfile
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var name: String

    init(
        index: Int,
        profile: LayoutProfile,
        onRename: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.index = index
        self.profile = profile
        self.onRename = onRename
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("⌃⌥\(index + 1)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            TextField("Profile name", text: $name)
                .onSubmit { onRename(name) }
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: profile.name) { _, newName in
            if name != newName { name = newName }
        }
    }
}
