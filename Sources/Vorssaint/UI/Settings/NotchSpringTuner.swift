// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Tunes the island's open/close spring (duration ~0.63 s, bounce 0.2 at the
/// defaults, Apple snappy territory) with a live preview of how it moves,
/// Figma-panel style.
struct NotchSpringTunerPopover: View {
    @AppStorage(DefaultsKey.notchSpringMass) private var mass = NotchMotion.defaultSpringMass
    @AppStorage(DefaultsKey.notchSpringStiffness) private var stiffness = NotchMotion.defaultSpringStiffness
    @AppStorage(DefaultsKey.notchSpringDamping) private var damping = NotchMotion.defaultSpringDamping
    @ObservedObject private var l10n = L10n.shared

    private var locale: Locale { Locale(identifier: l10n.language.rawValue) }

    private var sanitized: (mass: Double, stiffness: Double, damping: Double) {
        (NotchMotion.sanitizedSpringMass(mass),
         NotchMotion.sanitizedSpringStiffness(stiffness),
         NotchMotion.sanitizedSpringDamping(damping))
    }

    private var spring: NotchMotion.Spring {
        let p = sanitized
        let mass = max(0.01, p.mass)
        let omega = (p.stiffness / mass).squareRoot()
        guard omega > 0 else { return NotchMotion.Spring(duration: NotchMotion.springBaselineDuration, bounce: 0) }
        let zeta = p.damping / (2 * (p.stiffness * mass).squareRoot())
        return NotchMotion.Spring(duration: 2 * Double.pi / omega, bounce: min(0.95, max(0, 1 - zeta)))
    }

    private var settlingMilliseconds: Int {
        let p = sanitized
        return Int((NotchMotion.referenceSettlingDuration(mass: p.mass, stiffness: p.stiffness,
                                                          damping: p.damping) * 1000).rounded())
    }

    private var isDefault: Bool {
        sanitized.mass == NotchMotion.defaultSpringMass
            && sanitized.stiffness == NotchMotion.defaultSpringStiffness
            && sanitized.damping == NotchMotion.defaultSpringDamping
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Opening spring").font(.headline)
                Spacer(minLength: 8)
                Text("\(settlingMilliseconds) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                    .help("Settling time at these values; the defaults settle in about 800 ms.")
            }
            NotchSpringPreview(mass: sanitized.mass, stiffness: sanitized.stiffness, damping: sanitized.damping)
                .frame(height: 132)
            NotchSpringCurve(spring: spring)
                .frame(height: 56)
            slider("Mass", value: $mass, in: NotchMotion.springMassRange, step: 0.1,
                   formatted: String(format: "%.1f", locale: locale, sanitized.mass))
            slider("Stiffness", value: $stiffness, in: NotchMotion.springStiffnessRange, step: 1,
                   formatted: "\(Int(sanitized.stiffness))")
            slider("Damping", value: $damping, in: NotchMotion.springDampingRange, step: 0.5,
                   formatted: String(format: "%.1f", locale: locale, sanitized.damping))
            HStack {
                Text("Snappy at the defaults, like the phone's island; lower damping bounces more.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Reset") {
                    mass = NotchMotion.defaultSpringMass
                    stiffness = NotchMotion.defaultSpringStiffness
                    damping = NotchMotion.defaultSpringDamping
                }
                .disabled(isDefault)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        step: Double, formatted: String) -> some View {
        let clamped = Binding(
            get: { min(range.upperBound, max(range.lowerBound, value.wrappedValue)) },
            set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) })
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(formatted).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: clamped, in: range, step: step) { Text(title) }
                .labelsHidden()
        }
    }
}

/// The island opening and closing on a loop with the tuner's spring,
/// drawn as the island draws itself: a black pill growing into the open
/// shape and settling back.
private struct NotchSpringPreview: View {
    let mass: Double
    let stiffness: Double
    let damping: Double

    private var spring: NotchMotion.Spring {
        let omega = (stiffness / max(0.01, mass)).squareRoot()
        guard omega > 0 else { return NotchMotion.Spring(duration: 0.6, bounce: 0) }
        let zeta = damping / (2 * (stiffness * max(0.01, mass)).squareRoot())
        return NotchMotion.Spring(duration: 2 * Double.pi / omega, bounce: min(0.95, max(0, 1 - zeta)))
    }

    /// Open, hold, close, hold.
    private var cycle: TimeInterval { openDuration + 0.45 + openDuration + 0.45 }

    private var openDuration: TimeInterval {
        // What the island waits for: the size stays within half a point for good.
        let from = CGSize(width: 126, height: 28)
        let to = CGSize(width: 252, height: 108)
        let step = 1.0 / 240
        var settled = step
        var time = step
        while time < 2 {
            func side(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
                start + (end - start) * CGFloat(spring.progress(at: time))
            }
            let size = CGSize(width: side(from.width, to.width), height: side(from.height, to.height))
            let back = CGSize(width: side(to.width, from.width), height: side(to.height, from.height))
            if abs(size.width - to.width) > 0.5 || abs(size.height - to.height) > 0.5
                || abs(back.width - from.width) > 0.5 || abs(back.height - from.height) > 0.5 {
                settled = time + step
            }
            time += step
        }
        return min(1.2, max(0.15, settled))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 60)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            let progress = progress(at: elapsed)
            let opening = isOpening(at: elapsed)
            let width = 126 + (252 - 126) * progress
            let height = 28 + (108 - 28) * progress
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(0.06))
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: min(14, height / 2), style: .continuous)
                        .fill(.black)
                        .frame(width: width, height: height)
                        .overlay {
                            if progress > 0.55 {
                                HStack(spacing: 6) {
                                    Circle().fill(.white.opacity(0.85)).frame(width: 8, height: 8)
                                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.35))
                                        .frame(width: 64 * min(1, (progress - 0.55) * 2.5), height: 7)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14)
                                .opacity(min(1, (progress - 0.55) * 4))
                            }
                        }
                    Text(opening ? "Opening" : "Closing")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .accessibilityHidden(true)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary, lineWidth: 1) }
    }

    /// Progress 0→1 through the cycle.
    private func progress(at elapsed: TimeInterval) -> Double {
        let open = openDuration
        if elapsed < open { return spring.progress(at: elapsed) }
        if elapsed < open + 0.45 { return 1 }
        if elapsed < open + 0.45 + open { return 1 - spring.progress(at: elapsed - open - 0.45) }
        return 0
    }

    private func isOpening(at elapsed: TimeInterval) -> Bool {
        elapsed < openDuration + 0.45
    }
}

/// The spring's progress over its duration, with the target as a dashed
/// line so overshoot reads at a glance.
private struct NotchSpringCurve: View {
    let spring: NotchMotion.Spring

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let samples = 120
            let points = (0...samples).map { i -> CGPoint in
                let t = Double(i) / Double(samples) * spring.duration
                let p = spring.progress(at: t)
                // Leave headroom above the target for the overshoot.
                let maxP = max(1.15, 1 + spring.overshoot * 1.2)
                return CGPoint(x: size.width * CGFloat(i) / CGFloat(samples),
                               y: size.height - size.height * CGFloat(p / maxP))
            }
            Path { path in
                path.addLines(points)
            }
            .stroke(Color.accentColor, lineWidth: 1.5)
            Path { path in
                let maxP = max(1.15, 1 + spring.overshoot * 1.2)
                let y = size.height - size.height * CGFloat(1 / maxP)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .accessibilityHidden(true)
    }
}
