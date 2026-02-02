//
//  SkillsSettingsView.swift
//  Motive
//
//  Skills management UI (Aurora Design System).
//

import SwiftUI

struct SkillsSettingsView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @ObservedObject private var registry = SkillRegistry.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space6) {
            SettingsCard(title: L10n.Settings.skillsSystem, icon: "sparkles") {
                SettingsRow(
                    label: L10n.Settings.skillsEnable,
                    description: L10n.Settings.skillsEnableDesc,
                    showDivider: false
                ) {
                    Toggle("", isOn: $configManager.skillsSystemEnabled)
                        .toggleStyle(.switch)
                        .tint(Color.Aurora.accent)
                        .onChange(of: configManager.skillsSystemEnabled) { _, _ in
                            registry.refresh()
                        }
                }
            }

            SettingsCard(title: L10n.Settings.skillsList, icon: "list.bullet") {
                if registry.entries.isEmpty {
                    emptyStateView
                } else {
                    ForEach(registry.entries) { entry in
                        SettingsRow(
                            label: entry.name,
                            description: statusDescription(for: entry),
                            showDivider: entry.id != registry.entries.last?.id
                        ) {
                            Toggle("", isOn: skillEnabledBinding(for: entry))
                                .toggleStyle(.switch)
                                .tint(Color.Aurora.accent)
                                .disabled(!configManager.skillsSystemEnabled)
                        }
                    }
                }
            }

            // Actions row
            HStack(spacing: AuroraSpacing.space3) {
                Spacer()
                
                Button {
                    registry.refresh()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text(L10n.Settings.skillsRefresh)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color.Aurora.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                            .strokeBorder(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        HStack {
            VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                Text(L10n.Settings.skillsNoSkills)
                    .font(.Aurora.body.weight(.medium))
                    .foregroundColor(Color.Aurora.textSecondary)
                
                Text(L10n.Settings.skillsNoSkillsDesc)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, AuroraSpacing.space4)
        .padding(.vertical, AuroraSpacing.space4)
    }

    private func statusDescription(for entry: SkillEntry) -> String {
        let source = entry.source.rawValue
        if entry.eligibility.isEligible {
            return "\(L10n.Settings.skillsEligible) • \(source)"
        }
        let reasons = entry.eligibility.reasons.joined(separator: ", ")
        return "\(L10n.Settings.skillsIneligible): \(reasons) • \(source)"
    }

    private func skillEnabledBinding(for entry: SkillEntry) -> Binding<Bool> {
        Binding(
            get: {
                configManager.skillEntryConfig(for: entry.name)?.enabled ?? true
            },
            set: { newValue in
                configManager.updateSkillEntryConfig(name: entry.name) { config in
                    config.enabled = newValue
                }
                registry.refresh()
            }
        )
    }
}
