// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How the command bar invokes: a stack of transition layers that play
/// together when the bar opens, and a second stack when it closes. Pure
/// data, so the rules are pinned by tests and the service only plays them.
///
/// Stored as a JSON string under `DefaultsKey.commandBarAppearTransition`.
/// Empty or unreadable means the built-in default below. The Settings page
/// edits a draft of this value and copies it out as JSON, so a config handed
/// back later pastes straight in.
struct CommandBarAppearTransition: Codable, Equatable {
    /// One animated property, from `from` to `to`, over `duration` seconds
    /// after `delay`. Several layers with the same timing compose into one
    /// motion; staggered delays compose into a sequence.
    struct Layer: Codable, Equatable, Identifiable {
        /// What moves. Raw values are storage ids, so they never change.
        enum Kind: String, Codable, CaseIterable {
            /// Layer opacity 0...1.
            case fade
            /// Uniform scale about the bar's centre (1 is resting size).
            case scale
            /// Horizontal scale only, about the centre.
            case stretchX
            /// Vertical scale only, about the centre.
            case stretchY
            /// Horizontal shift in points. Positive moves right.
            case slideX
            /// Vertical shift in points. Positive moves up.
            case slideY
            /// Gaussian blur radius in points.
            case blur
        }

        /// How the layer gets there. Raw values are storage ids.
        enum Curve: String, Codable, CaseIterable {
            /// Constant speed.
            case linear
            /// Fast out, soft landing.
            case gentle
            /// Fast in the middle, soft at both ends.
            case quick
            /// A real spring, tuned by mass/stiffness/damping below.
            case spring
        }

        var id: String
        var kind: Kind
        var from: Double
        var to: Double
        var duration: TimeInterval
        var delay: TimeInterval
        var curve: Curve
        var mass: Double
        var stiffness: Double
        var damping: Double

        init(id: String = UUID().uuidString,
             kind: Kind,
             from: Double,
             to: Double,
             duration: TimeInterval,
             delay: TimeInterval = 0,
             curve: Curve,
             mass: Double = 1,
             stiffness: Double = 400,
             damping: Double = 28) {
            self.id = id
            self.kind = kind
            self.from = from
            self.to = to
            self.duration = duration
            self.delay = delay
            self.curve = curve
            self.mass = mass
            self.stiffness = stiffness
            self.damping = damping
        }
    }

    /// The island drop's own timing, as scales on its built-in motion. The
    /// liquid path math stays untouched; only its pace changes.
    struct DropletTuning: Codable, Equatable {
        /// Multiplies every leg of the fall, hurry and retract.
        var durationScale: Double
        /// How long the drop takes to fade off the landed bar.
        var fadeDuration: TimeInterval

        static let `default` = DropletTuning(durationScale: 1, fadeDuration: 0.14)
    }

    var openLayers: [Layer]
    var closeLayers: [Layer]
    /// True grows the window around a scale intro and animates the frame
    /// home, the way the old appear did. False (the default) leaves the
    /// window exactly where `position()` put it and animates the layer only,
    /// so the bar can never read as sliding in from the side.
    var followWindow: Bool
    var droplet: DropletTuning

    // MARK: - Limits

    static let maxLayers = 8
    static let durationRange: ClosedRange<Double> = 0...1
    static let delayRange: ClosedRange<Double> = 0...1
    static let fadeRange: ClosedRange<Double> = 0...1
    static let scaleRange: ClosedRange<Double> = 0.5...1.5
    static let slideRange: ClosedRange<Double> = -64...64
    static let blurRange: ClosedRange<Double> = 0...24
    static let massRange: ClosedRange<Double> = 0.1...4
    static let stiffnessRange: ClosedRange<Double> = 10...400
    static let dampingRange: ClosedRange<Double> = 1...40
    static let dropletPaceRange: ClosedRange<Double> = 0.25...2
    static let dropletFadeRange: ClosedRange<Double> = 0...0.5

    /// Ships quiet and instant-ish: a short fade with a whisper of scale,
    /// no window-frame travel. Anything louder is one layer away.
    static let `default` = CommandBarAppearTransition(
        openLayers: [
            Layer(kind: .fade, from: 0, to: 1, duration: 0.12, curve: .gentle),
            Layer(kind: .scale, from: 1.03, to: 1, duration: 0.16, curve: .gentle),
        ],
        closeLayers: [
            Layer(kind: .fade, from: 1, to: 0, duration: 0.1, curve: .linear),
        ],
        followWindow: false,
        droplet: .default)

    // MARK: - Storage

    /// Reads the stored JSON, or the default when it is missing, broken or
    /// out of range. Never throws on the invoke path.
    static func decode(_ raw: String?) -> CommandBarAppearTransition {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CommandBarAppearTransition.self, from: data)
        else { return .default }
        return decoded.sanitized()
    }

    static func current(in defaults: UserDefaults = .standard) -> CommandBarAppearTransition {
        decode(defaults.string(forKey: DefaultsKey.commandBarAppearTransition))
    }

    /// Compact JSON for storage.
    func encode() -> String {
        guard let data = try? JSONEncoder().encode(sanitized()) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Indented JSON for the Copy config button: what the person hands back
    /// to make it the new default.
    func encodedPretty() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sanitized()) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Rules

    func sanitized() -> CommandBarAppearTransition {
        var next = self
        next.openLayers = Layer.sanitizedList(openLayers)
        next.closeLayers = Layer.sanitizedList(closeLayers)
        next.droplet = droplet.sanitized()
        return next
    }

    /// When the last open layer lands, for completion timing.
    var openRunTime: TimeInterval {
        openLayers.map { $0.delay + $0.duration }.max() ?? 0
    }

    /// When the last close layer lands, for completion timing.
    var closeRunTime: TimeInterval {
        closeLayers.map { $0.delay + $0.duration }.max() ?? 0
    }

    /// The largest resting-size multiple any scale layer starts from, for
    /// the optional window-frame follow. 1 when nothing scales.
    var maxScaleFrom: Double {
        var biggest = 1.0
        for layer in openLayers {
            switch layer.kind {
            case .scale, .stretchX, .stretchY:
                biggest = max(biggest, layer.from, layer.to)
            case .fade, .slideX, .slideY, .blur:
                break
            }
        }
        return biggest
    }
}

extension CommandBarAppearTransition.Layer {
    static func sanitizedList(_ layers: [CommandBarAppearTransition.Layer]) -> [CommandBarAppearTransition.Layer] {
        var seen = Set<String>()
        var kept: [CommandBarAppearTransition.Layer] = []
        for layer in layers {
            guard kept.count < CommandBarAppearTransition.maxLayers else { break }
            kept.append(layer.sanitized(makingIDUniqueIn: &seen))
        }
        return kept
    }

    func valueRange() -> ClosedRange<Double> {
        switch kind {
        case .fade: return CommandBarAppearTransition.fadeRange
        case .scale, .stretchX, .stretchY: return CommandBarAppearTransition.scaleRange
        case .slideX, .slideY: return CommandBarAppearTransition.slideRange
        case .blur: return CommandBarAppearTransition.blurRange
        }
    }

    func sanitized(makingIDUniqueIn seen: inout Set<String>) -> CommandBarAppearTransition.Layer {
        var next = self
        if next.id.isEmpty || !seen.insert(next.id).inserted {
            var fresh = UUID().uuidString
            while !seen.insert(fresh).inserted { fresh = UUID().uuidString }
            next.id = fresh
        }
        next.duration = clamped(next.duration, in: CommandBarAppearTransition.durationRange)
        next.delay = clamped(next.delay, in: CommandBarAppearTransition.delayRange)
        let range = next.valueRange()
        next.from = clamped(next.from, in: range)
        next.to = clamped(next.to, in: range)
        next.mass = clamped(next.mass, in: CommandBarAppearTransition.massRange)
        next.stiffness = clamped(next.stiffness, in: CommandBarAppearTransition.stiffnessRange)
        next.damping = clamped(next.damping, in: CommandBarAppearTransition.dampingRange)
        return next
    }

    private func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

extension CommandBarAppearTransition.DropletTuning {
    func sanitized() -> CommandBarAppearTransition.DropletTuning {
        var next = self
        if !next.durationScale.isFinite { next.durationScale = 1 }
        next.durationScale = min(CommandBarAppearTransition.dropletPaceRange.upperBound,
                                 max(CommandBarAppearTransition.dropletPaceRange.lowerBound, next.durationScale))
        if !next.fadeDuration.isFinite { next.fadeDuration = CommandBarAppearTransition.DropletTuning.default.fadeDuration }
        next.fadeDuration = min(CommandBarAppearTransition.dropletFadeRange.upperBound,
                                max(CommandBarAppearTransition.dropletFadeRange.lowerBound, next.fadeDuration))
        return next
    }
}
