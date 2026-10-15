// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarAppearTransitionTests {
    static func run(_ suite: TestSuite) {
        // MARK: Decoding falls back to the default

        suite.expect(CommandBarAppearTransition.decode(nil) == .default,
                     "no stored transition means the built-in default")
        suite.expect(CommandBarAppearTransition.decode("") == .default,
                     "an empty stored transition means the built-in default")
        suite.expect(CommandBarAppearTransition.decode("not json") == .default,
                     "a broken stored transition never breaks the invoke")
        suite.expect(CommandBarAppearTransition.decode("{\"kind\":\"nope\"}") == .default,
                     "an unknown shape falls back instead of half-applying")

        // MARK: The default ships quiet and never moves the window

        suite.expect(!CommandBarAppearTransition.default.followWindow,
                     "the default transition leaves the window where position() put it")
        suite.expect(!CommandBarAppearTransition.default.openLayers.isEmpty
                     && CommandBarAppearTransition.default.openLayers.allSatisfy { $0.duration <= 0.2 },
                     "the default open is a whisper, never a wait")
        suite.expect(CommandBarAppearTransition.default.closeRunTime <= 0.2,
                     "the default close lands within a beat")

        // MARK: Round trips keep every layer

        let stacked = CommandBarAppearTransition(
            openLayers: [
                .init(kind: .fade, from: 0, to: 1, duration: 0.12, curve: .gentle),
                .init(kind: .scale, from: 1.1, to: 1, duration: 0.3, curve: .spring,
                      mass: 1, stiffness: 400, damping: 28),
                .init(kind: .slideY, from: 8, to: 0, duration: 0.2, delay: 0.05, curve: .quick),
                .init(kind: .blur, from: 6, to: 0, duration: 0.2, curve: .linear),
            ],
            closeLayers: [
                .init(kind: .fade, from: 1, to: 0, duration: 0.1, curve: .linear),
            ],
            followWindow: true,
            droplet: .init(durationScale: 1.5, fadeDuration: 0.2))
        let roundTripped = CommandBarAppearTransition.decode(stacked.encode())
        suite.expect(roundTripped == stacked.sanitized(),
                     "a stacked config survives storage unchanged")
        let pretty = stacked.encodedPretty()
        suite.expect(!pretty.isEmpty
                     && (try? JSONDecoder().decode(CommandBarAppearTransition.self,
                                                   from: Data(pretty.utf8))) != nil,
                     "the copied config is JSON that decodes again")

        // MARK: Sanitizing clamps, never corrupts

        let wild = CommandBarAppearTransition(
            openLayers: [
                .init(id: "", kind: .fade, from: -2, to: 9, duration: 5, delay: -1,
                      curve: .linear, mass: .nan, stiffness: .infinity, damping: -3),
                .init(id: "same", kind: .scale, from: 9, to: -9, duration: 0.2, curve: .gentle),
                .init(id: "same", kind: .slideX, from: -900, to: 900, duration: 0.2, curve: .quick),
                .init(id: "same", kind: .blur, from: 0, to: 100, duration: 0.2, curve: .linear),
            ],
            closeLayers: (0..<20).map {
                .init(id: "close-\($0)", kind: .fade, from: 1, to: 0, duration: 0.1, curve: .linear)
            },
            followWindow: true,
            droplet: .init(durationScale: 99, fadeDuration: .nan))
        let sane = wild.sanitized()
        let first = sane.openLayers[0]
        suite.expect(first.duration == 1 && first.delay == 0
                     && first.from == 0 && first.to == 1
                     && first.mass == 0.1 && first.stiffness == 10 && first.damping == 1,
                     "out-of-range timing and spring values clamp to their ranges")
        suite.expect(sane.openLayers[1].from == 1.5 && sane.openLayers[1].to == 0.5,
                     "a scale layer cannot leave its resting-size multiple")
        suite.expect(sane.openLayers[2].from == -64 && sane.openLayers[2].to == 64,
                     "a slide layer cannot leave the screen")
        suite.expect(sane.openLayers[3].to == 24,
                     "a blur layer cannot ask for more than its radius cap")
        suite.expect(Set(sane.openLayers.map(\.id)).count == sane.openLayers.count
                     && sane.openLayers.allSatisfy({ !$0.id.isEmpty }),
                     "every layer keeps a unique id after sanitizing")
        suite.expect(sane.closeLayers.count == CommandBarAppearTransition.maxLayers,
                     "the stacks stop growing instead of piling up")
        suite.expect(sane.droplet.durationScale == 2
                     && sane.droplet.fadeDuration == CommandBarAppearTransition.DropletTuning.default.fadeDuration,
                     "a wild droplet pace clamps, and a missing fade falls back")

        // MARK: Timing helpers

        let timed = CommandBarAppearTransition(
            openLayers: [
                .init(kind: .fade, from: 0, to: 1, duration: 0.2, delay: 0.05, curve: .linear),
            ],
            closeLayers: [],
            followWindow: false,
            droplet: .default)
        suite.expect(timed.openRunTime == 0.25 && timed.closeRunTime == 0,
                     "run times add each layer's delay to its duration")
        suite.expect(CommandBarAppearTransition.default.maxScaleFrom < 1.1
                     && stacked.maxScaleFrom == 1.1,
                     "the window follow only grows around the largest scale asked for")

        // MARK: Value ranges per kind

        suite.expect(CommandBarAppearTransition.Layer(kind: .fade, from: 0, to: 1,
                                                      duration: 0.1, curve: .linear).valueRange() == 0...1
                     && CommandBarAppearTransition.Layer(kind: .slideY, from: 0, to: 8,
                                                        duration: 0.1, curve: .linear).valueRange() == -64...64,
                     "each kind clamps to its own units")

        // MARK: Wiring

        suite.expect(Defaults.registeredDefaults[DefaultsKey.commandBarAppearTransition] as? String == "",
                     "the transition starts at its built-in default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.commandBarAppearTransition),
                     "the transition is configuration, so it travels with an exported setup")
        suite.expect(SettingsBackupSupport.valueLooksRight(DefaultsKey.commandBarAppearTransition, "{}")
                     && !SettingsBackupSupport.valueLooksRight(DefaultsKey.commandBarAppearTransition, true),
                     "a restored transition has to be text, not a switch")

        let domain = "com.vorssaint.tests.command-bar-transition"
        let stored = UserDefaults(suiteName: domain)!
        stored.removePersistentDomain(forName: domain)
        suite.expect(CommandBarAppearTransition.current(in: stored) == .default,
                     "an untouched store reads the built-in default")
        stored.set(stacked.encode(), forKey: DefaultsKey.commandBarAppearTransition)
        suite.expect(CommandBarAppearTransition.current(in: stored) == stacked.sanitized(),
                     "what the editor saved is what the next invoke plays")
        stored.set("broken", forKey: DefaultsKey.commandBarAppearTransition)
        suite.expect(CommandBarAppearTransition.current(in: stored) == .default,
                     "a broken store never breaks the invoke")
        stored.removePersistentDomain(forName: domain)
    }
}
