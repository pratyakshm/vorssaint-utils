// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ProcessUsageRow: View {
    let row: ProcessUsage
    let value: String
    var iconSize: CGFloat = 15
    var leadingPadding: CGFloat = 0

    @Environment(\.notchPresentation) private var inNotch
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Group {
            if AppFeature.killProcess.isAvailable {
                activatableContent
                    .contextMenu {
                        Button(FeatureStrings.killProcess(l10n.language).forceKillButton,
                               role: .destructive) {
                            ProcessUsageService.shared.confirmForceQuit(row, inNotch: inNotch)
                        }
                        .disabled(!ProcessUsageService.shared.canForceQuit(row))
                    }
            } else {
                activatableContent
            }
        }
        .help(row.name)
    }

    private var activatableContent: some View {
        Group {
            if ProcessUsageService.shared.canActivate(row) {
                Button {
                    ProcessUsageService.shared.activate(row)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: DS.Space.rowTitleGap) {
            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                .resizable()
                .frame(width: iconSize, height: iconSize)
            Text(row.name)
                .font(DS.Font.panelFloor)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(value)
                .font(DS.Font.panelFloorEmphasis)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.leading, leadingPadding)
    }
}
