// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Puts every display to sleep right now while the Mac keeps running.
///
/// One route for every caller: the command bar's "Sleep Displays" system
/// action, the Quick toggles "Turn off the display" row and the optional
/// sleep-on-lid-close. `pmset displaysleepnow` needs no permission, keeps
/// power assertions (notably a Keep Awake session) in effect and wakes on
/// any key, click or lid open.
enum DisplaySleep {
    /// True when the request was accepted. Callers run this off the main
    /// thread: the tool can block briefly.
    @discardableResult
    static func sleepNow() -> Bool {
        Shell.run("/usr/bin/pmset", ["displaysleepnow"]).status == 0
    }
}
