import KTAppleCore
import SwiftUI

/// List of auto-assignment rules with an "Add Rule" button.
struct RulesView: View {
    @State private var rules: [AppRule]
    let displayIDs: [UInt32]
    let leafCounts: [UInt32: Int]
    let onAddRule: (AppRule) -> Void
    let onDeleteRule: (UUID) -> Void

    @State private var showingAddSheet = false

    init(
        rules: [AppRule],
        displayIDs: [UInt32],
        leafCounts: [UInt32: Int],
        onAddRule: @escaping (AppRule) -> Void,
        onDeleteRule: @escaping (UUID) -> Void
    ) {
        _rules = State(initialValue: rules)
        self.displayIDs = displayIDs
        self.leafCounts = leafCounts
        self.onAddRule = onAddRule
        self.onDeleteRule = onDeleteRule
    }

    var body: some View {
        if rules.isEmpty {
            Text("No rules yet. Add a rule to auto-assign app windows to tiles.")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.vertical, 4)
        } else {
            ForEach(rules) { rule in
                RuleRow(rule: rule, onDelete: {
                    rules.removeAll { $0.id == rule.id }
                    onDeleteRule(rule.id)
                })
            }
        }
        Button("Add Rule...") {
            showingAddSheet = true
        }
        .sheet(isPresented: $showingAddSheet) {
            AddRuleSheet(
                displayIDs: displayIDs,
                leafCounts: leafCounts,
                onAdd: { rule in
                    rules.append(rule)
                    onAddRule(rule)
                    showingAddSheet = false
                },
                onCancel: {
                    showingAddSheet = false
                }
            )
        }
    }
}

// MARK: - RuleRow

private struct RuleRow: View {
    let rule: AppRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.appName)
                    .font(.body)
                Text(rule.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Display \(rule.displayID) / Tile \(rule.tileIndex + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}
