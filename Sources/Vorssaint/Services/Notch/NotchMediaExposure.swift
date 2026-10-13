// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// App-side store for per-app media exposure: bundle identifiers the island
/// never shows. App target only — never add this file to the Now Playing
/// adapter compile line in `build.sh`, which cannot see `DefaultsKey`.
/// The hidden set is read once per use (no observers, no cache), so hiding
/// apps costs nothing at rest.
enum NotchMediaExposureStore {
    static func hidden(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: DefaultsKey.notchMediaHiddenApps) ?? [])
    }

    static func setHidden(_ hidden: Bool, bundleIdentifier: String,
                          in defaults: UserDefaults = .standard) {
        var current = self.hidden(in: defaults)
        if hidden { current.insert(bundleIdentifier) } else { current.remove(bundleIdentifier) }
        defaults.set(current.sorted(), forKey: DefaultsKey.notchMediaHiddenApps)
    }
}
