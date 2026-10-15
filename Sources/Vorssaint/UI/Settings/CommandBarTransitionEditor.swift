// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Edits how the command bar invokes: a stack of transition layers for
/// opening and another for closing, each with its own kind, timing and
/// curve. The Copy config button writes the whole setup as JSON, which is
/// the format to hand back when asking for a tuned default.
struct CommandBarTransitionEditor: View {
    @AppStorage(DefaultsKey.commandBarAppearTransition) private var stored = ""
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = CommandBarAppearTransition.default
    @State private var importText = ""
    @State private var importError: String?
    @State private var copied = false

    private var locale: Locale { Locale(identifier: l10n.language.rawValue) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.rowGap) {
                Text("Invoke transition")
                    .font(DS.Font.cardTitle)
                Text("Layers play together when the bar opens and when it closes. Empty means instant.")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                layerGroup(title: "Open", layers: $draft.openLayers, isOpen: true)
                layerGroup(title: "Close", layers: $draft.closeLayers, isOpen: false)
                Toggle("Window follows the scale", isOn: $draft.followWindow)
                    .font(DS.Font.body)
                    .onChange(of: draft.followWindow) { _, _ in save() }
                Text("Off, the window never moves and only the bar itself animates. On, the window grows around a scale intro and travels home behind it.")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                dropletGroup
                HStack(spacing: DS.Space.medium) {
                    Button("Preview") { CommandBarService.shared.show() }
                    Button("Reset to defaults") {
                        draft = .default
                        save()
                    }
                    .disabled(draft == .default)
                    Spacer()
                    Button(copied ? "Copied" : "Copy config") { copyConfig() }
                        .buttonStyle(.borderedProminent)
                }
                importGroup
            }
            .padding(DS.Space.xLarge)
        }
        .frame(width: 520, height: 560)
        .onAppear { draft = CommandBarAppearTransition.decode(stored) }
    }

    // MARK: - Layer stacks

    private func layerGroup(title: String,
                            layers: Binding<[CommandBarAppearTransition.Layer]>,
                            isOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xSmall) {
            HStack {
                Text(title)
                    .font(DS.Font.rowTitle)
                Spacer()
                Menu("Add layer") {
                    ForEach(CommandBarAppearTransition.Layer.Kind.allCases, id: \.self) { kind in
                        Button(kindTitle(kind)) {
                            addLayer(kind: kind, to: layers, isOpen: isOpen)
                        }
                    }
                }
                .disabled(layers.wrappedValue.count >= CommandBarAppearTransition.maxLayers)
            }
            if layers.wrappedValue.isEmpty {
                Text(isOpen ? "No motion: the bar appears at once."
                    : "No motion: the bar leaves at once.")
                    .font(DS.Font.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(layers) { $layer in
                layerRow(layer: $layer,
                         canMoveUp: layers.wrappedValue.first?.id != layer.id,
                         canMoveDown: layers.wrappedValue.last?.id != layer.id,
                         onMoveUp: { move(layer, in: layers, by: -1) },
                         onMoveDown: { move(layer, in: layers, by: 1) },
                         onDelete: { delete(layer, from: layers) })
            }
        }
    }

    private func layerRow(layer: Binding<CommandBarAppearTransition.Layer>,
                          canMoveUp: Bool, canMoveDown: Bool,
                          onMoveUp: @escaping () -> Void,
                          onMoveDown: @escaping () -> Void,
                          onDelete: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xSmall) {
            HStack(spacing: DS.Space.xSmall) {
                Picker("", selection: layer.kind) {
                    ForEach(CommandBarAppearTransition.Layer.Kind.allCases, id: \.self) { kind in
                        Text(kindTitle(kind)).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
                .onChange(of: layer.wrappedValue.kind) { _, _ in save() }
                Spacer()
                Button("↑") { onMoveUp() }.disabled(!canMoveUp)
                Button("↓") { onMoveDown() }.disabled(!canMoveDown)
                Button("Remove") { onDelete() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            HStack(spacing: DS.Space.xSmall) {
                Text("From")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Slider(value: layer.from, in: layer.wrappedValue.valueRange(), step: layerStep(layer.wrappedValue.kind))
                    .onChange(of: layer.wrappedValue.from) { _, _ in save() }
                Text(layerValue(layer.wrappedValue.from, kind: layer.wrappedValue.kind))
                    .font(DS.Font.panelFloor)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                    .monospacedDigit()
            }
            HStack(spacing: DS.Space.xSmall) {
                Text("To")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                Slider(value: layer.to, in: layer.wrappedValue.valueRange(), step: layerStep(layer.wrappedValue.kind))
                    .onChange(of: layer.wrappedValue.to) { _, _ in save() }
                Text(layerValue(layer.wrappedValue.to, kind: layer.wrappedValue.kind))
                    .font(DS.Font.panelFloor)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                    .monospacedDigit()
            }
            Picker("", selection: layer.curve) {
                ForEach(CommandBarAppearTransition.Layer.Curve.allCases, id: \.self) { curve in
                    Text(curveTitle(curve)).tag(curve)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: layer.wrappedValue.curve) { _, _ in save() }
            if layer.wrappedValue.curve == .spring {
                springControls(layer: layer)
            } else {
                HStack(spacing: DS.Space.xSmall) {
                    Text("Duration")
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Slider(value: layer.duration, in: 0...1, step: 0.01)
                        .onChange(of: layer.wrappedValue.duration) { _, _ in save() }
                    Text("\(Int((layer.wrappedValue.duration * 1000).rounded())) ms")
                        .font(DS.Font.panelFloor)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                        .monospacedDigit()
                }
                HStack(spacing: DS.Space.xSmall) {
                    Text("Delay")
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Slider(value: layer.delay, in: 0...0.5, step: 0.01)
                        .onChange(of: layer.wrappedValue.delay) { _, _ in save() }
                    Text("\(Int((layer.wrappedValue.delay * 1000).rounded())) ms")
                        .font(DS.Font.panelFloor)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                        .monospacedDigit()
                }
            }
        }
        .padding(DS.Space.small)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func springControls(layer: Binding<CommandBarAppearTransition.Layer>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xSmall) {
            springSlider(title: "Mass", value: layer.mass, in: 0.1...4, step: 0.1, places: 1)
            springSlider(title: "Stiffness", value: layer.stiffness, in: 10...400, step: 1, places: 0)
            springSlider(title: "Damping", value: layer.damping, in: 1...40, step: 0.5, places: 1)
            HStack {
                Text("Settles in \(settleMilliseconds(layer.wrappedValue)) ms")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("Delay")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                Slider(value: layer.delay, in: 0...0.5, step: 0.01)
                    .frame(width: 110)
                    .onChange(of: layer.wrappedValue.delay) { _, _ in save() }
            }
        }
        .onChange(of: layer.wrappedValue.mass) { _, _ in save() }
        .onChange(of: layer.wrappedValue.stiffness) { _, _ in save() }
        .onChange(of: layer.wrappedValue.damping) { _, _ in save() }
    }

    private func springSlider(title: String, value: Binding<Double>,
                              in range: ClosedRange<Double>, step: Double, places: Int) -> some View {
        HStack(spacing: DS.Space.xSmall) {
            Text(title)
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.\(places)f", locale: locale, value.wrappedValue))
                .font(DS.Font.panelFloor)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
                .monospacedDigit()
        }
    }

    // MARK: - Droplet

    private var dropletGroup: some View {
        VStack(alignment: .leading, spacing: DS.Space.xSmall) {
            Text("Island drop")
                .font(DS.Font.rowTitle)
            HStack(spacing: DS.Space.xSmall) {
                Text("Pace")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Slider(value: $draft.droplet.durationScale, in: 0.25...2, step: 0.05)
                    .onChange(of: draft.droplet.durationScale) { _, _ in save() }
                Text(String(format: "%.2fx", locale: locale, draft.droplet.durationScale))
                    .font(DS.Font.panelFloor)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                    .monospacedDigit()
            }
            HStack(spacing: DS.Space.xSmall) {
                Text("Fade off")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Slider(value: $draft.droplet.fadeDuration, in: 0...0.5, step: 0.01)
                    .onChange(of: draft.droplet.fadeDuration) { _, _ in save() }
                Text("\(Int((draft.droplet.fadeDuration * 1000).rounded())) ms")
                    .font(DS.Font.panelFloor)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Config in and out

    private var importGroup: some View {
        VStack(alignment: .leading, spacing: DS.Space.xSmall) {
            Text("Paste a config to apply it")
                .font(DS.Font.rowTitle)
            TextEditor(text: $importText)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
            if let importError {
                Text(importError)
                    .font(DS.Font.caption)
                    .foregroundStyle(.orange)
            }
            Button("Apply pasted config") { importConfig() }
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Mutations

    private func save() {
        draft = draft.sanitized()
        stored = draft.encode()
    }

    private func addLayer(kind: CommandBarAppearTransition.Layer.Kind,
                          to layers: Binding<[CommandBarAppearTransition.Layer]>,
                          isOpen: Bool) {
        let layer = CommandBarAppearTransition.Layer(
            kind: kind,
            from: defaultFrom(kind: kind, isOpen: isOpen),
            to: defaultTo(kind: kind, isOpen: isOpen),
            duration: 0.15, curve: .gentle)
        layers.wrappedValue.append(layer)
        save()
    }

    private func defaultFrom(kind: CommandBarAppearTransition.Layer.Kind, isOpen: Bool) -> Double {
        switch kind {
        case .fade: return isOpen ? 0 : 1
        case .scale, .stretchX, .stretchY: return isOpen ? 1.05 : 1
        case .slideX: return isOpen ? -12 : 0
        case .slideY: return isOpen ? 8 : 0
        case .blur: return isOpen ? 6 : 0
        }
    }

    private func defaultTo(kind: CommandBarAppearTransition.Layer.Kind, isOpen: Bool) -> Double {
        switch kind {
        case .fade: return isOpen ? 1 : 0
        case .scale, .stretchX, .stretchY: return isOpen ? 1 : 1.05
        case .slideX: return isOpen ? 0 : -12
        case .slideY: return isOpen ? 0 : 8
        case .blur: return isOpen ? 0 : 6
        }
    }

    private func move(_ layer: CommandBarAppearTransition.Layer,
                      in layers: Binding<[CommandBarAppearTransition.Layer]>, by offset: Int) {
        guard let index = layers.wrappedValue.firstIndex(where: { $0.id == layer.id }) else { return }
        let next = index + offset
        guard layers.wrappedValue.indices.contains(next) else { return }
        layers.wrappedValue.move(fromOffsets: IndexSet(integer: index), toOffset: next > index ? next + 1 : next)
        save()
    }

    private func delete(_ layer: CommandBarAppearTransition.Layer,
                        from layers: Binding<[CommandBarAppearTransition.Layer]>) {
        layers.wrappedValue.removeAll { $0.id == layer.id }
        save()
    }

    private func copyConfig() {
        let json = draft.sanitized().encodedPretty()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func importConfig() {
        guard let data = importText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CommandBarAppearTransition.self, from: data) else {
            importError = "That text is not a transition config."
            return
        }
        importError = nil
        draft = decoded.sanitized()
        save()
    }

    // MARK: - Labels

    private func kindTitle(_ kind: CommandBarAppearTransition.Layer.Kind) -> String {
        switch kind {
        case .fade: return "Fade"
        case .scale: return "Scale"
        case .stretchX: return "Stretch X"
        case .stretchY: return "Stretch Y"
        case .slideX: return "Slide X"
        case .slideY: return "Slide Y"
        case .blur: return "Blur"
        }
    }

    private func curveTitle(_ curve: CommandBarAppearTransition.Layer.Curve) -> String {
        switch curve {
        case .linear: return "Linear"
        case .gentle: return "Gentle"
        case .quick: return "Quick"
        case .spring: return "Spring"
        }
    }

    private func layerStep(_ kind: CommandBarAppearTransition.Layer.Kind) -> Double {
        switch kind {
        case .fade: return 0.05
        case .scale, .stretchX, .stretchY: return 0.01
        case .slideX, .slideY: return 1
        case .blur: return 0.5
        }
    }

    private func layerValue(_ value: Double, kind: CommandBarAppearTransition.Layer.Kind) -> String {
        switch kind {
        case .fade: return String(format: "%.2f", locale: locale, value)
        case .scale, .stretchX, .stretchY: return String(format: "%.2fx", locale: locale, value)
        case .slideX, .slideY: return "\(Int(value))pt"
        case .blur: return String(format: "%.1f", locale: locale, value)
        }
    }

    private func settleMilliseconds(_ layer: CommandBarAppearTransition.Layer) -> Int {
        let spring = CASpringAnimation(keyPath: "opacity")
        spring.mass = layer.mass
        spring.stiffness = layer.stiffness
        spring.damping = layer.damping
        spring.fromValue = 0
        spring.toValue = 1
        spring.duration = spring.settlingDuration
        return Int((spring.settlingDuration * 1000).rounded())
    }
}
