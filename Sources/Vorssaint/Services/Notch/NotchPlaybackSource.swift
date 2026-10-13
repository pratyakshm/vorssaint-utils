// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Per-app media exposure helpers. Pure by design: this file also compiles
/// into the Now Playing adapter (`build.sh`), which never sees `DefaultsKey`,
/// so the hidden set is always passed in by app-side callers. Zero stored
/// state, zero cost when nothing is hidden.
enum NotchMediaExposure {
    static func isHidden(bundleIdentifier: String?, hidden: Set<String>) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return hidden.contains(bundleIdentifier)
    }

    static func excludingHidden(_ sources: [NotchPlaybackSource], hidden: Set<String>) -> [NotchPlaybackSource] {
        guard !hidden.isEmpty else { return sources }
        return sources.filter { !hidden.contains($0.bundleIdentifier) }
    }

    /// Common browsers and their helpers, for one-tap hiding.
    static let knownBrowsers: [String] = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.arc.net",
        "com.operasoftware.Opera",
        "org.chromium.Chromium",
        "app.zen-browser.zen",
        "com.vivaldi.Vivaldi",
    ]

    static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        let lower = bundleIdentifier.lowercased()
        if lower.contains("safari") || lower.contains("webkit.webcontent") { return true }
        if lower.contains("chrome") || lower.contains("chromium") { return true }
        if lower.contains("firefox") { return true }
        if lower.contains("edge") && lower.contains("microsoft") { return true }
        if lower.contains("brave") || lower.contains("arc.net") || lower.contains("opera")
            || lower.contains("vivaldi") || lower.contains("zen-browser") { return true }
        return knownBrowsers.contains(bundleIdentifier)
    }
}

struct NotchPlaybackSource: Equatable {
    struct Selection: Equatable {
        let pid: Int32
        let bundleIdentifier: String

        var isValid: Bool { pid > 0 && NotchPlaybackCommand.validIdentifier(bundleIdentifier) }
    }

    let pid: Int32
    let bundleIdentifier: String
    let isMusicApp: Bool
    let isPlaying: Bool
    let hasTrack: Bool
    var displayName: String? = nil

    var selection: Selection { Selection(pid: pid, bundleIdentifier: bundleIdentifier) }

    static func isMusicApplication(bundleIdentifier: String?, parentBundleIdentifier: String?, category: String?) -> Bool {
        let knownMusicApps: Set<String> = ["com.apple.Music", "com.apple.iTunes", "com.spotify.client"]
        return category == "public.app-category.music"
            || [bundleIdentifier, parentBundleIdentifier].compactMap { $0 }.contains(where: knownMusicApps.contains)
    }

    var reply: [String: Any] {
        var value: [String: Any] = ["pid": pid, "bundleIdentifier": bundleIdentifier, "isMusicApp": isMusicApp,
                                   "isPlaying": isPlaying, "hasTrack": hasTrack]
        value["displayName"] = displayName
        return value
    }

    /// A process identifier from the adapter: a positive whole number, never a Boolean.
    static func decodePID(_ value: Any?) -> Int32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: number.doubleValue), pid > 0 else { return nil }
        return pid
    }

    /// Only the chosen source is listed without a track: it stays chosen for
    /// a moment while it waits for its next one.
    static func decode(_ value: Any?, selectedPID: Int32? = nil) -> [Self] {
        guard let entries = value as? [[String: Any]], entries.count <= 16 else { return [] }
        var sources: [Self] = []
        for entry in entries {
            guard let pid = decodePID(entry["pid"]),
                  let bundle = entry["bundleIdentifier"] as? String, NotchPlaybackCommand.validIdentifier(bundle),
                  let music = entry["isMusicApp"] as? Bool, let playing = entry["isPlaying"] as? Bool,
                  let track = entry["hasTrack"] as? Bool, track || pid == selectedPID,
                  !sources.contains(where: { $0.pid == pid }) else { continue }
            let name = (entry["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            sources.append(Self(pid: pid, bundleIdentifier: bundle, isMusicApp: music, isPlaying: playing, hasTrack: track,
                                displayName: name.flatMap { !$0.isEmpty && $0.utf8.count <= 256 ? $0 : nil }))
        }
        return sources.sorted { $0.pid < $1.pid }
    }

    /// Automatic playback follows music apps and, unless the user turns them
    /// off, other players too. A manual source choice always takes precedence.
    /// Paused music keeps its resume control when nothing eligible is playing,
    /// except that a followed player that is not a music app keeps its place
    /// while paused.
    static func preferred(in sources: [Self], previousPID: Int32?, systemPID: Int32?, selection: Selection? = nil,
                          includeOtherPlayers: Bool = false) -> Self? {
        let available = sources.filter { $0.pid > 0 && $0.hasTrack }
        // An explicit choice remains controllable while paused, even if another
        // source is playing. Without a track, the automatic order fills in.
        if let selection, let chosen = available.first(where: { $0.selection == selection }) { return chosen }
        let music = available.filter(\.isMusicApp)
        // Registered clients can be playing while macOS still remembers a
        // paused music app as its system player. Other players follow their
        // live playback too; ownership only breaks a tie between eligible clients.
        let other = includeOtherPlayers ? available.filter { !$0.isMusicApp } : []
        // The followed player keeps its place while paused, so pausing a
        // video never switches playback to music paused earlier.
        for candidates in [music.filter(\.isPlaying), other.filter(\.isPlaying),
                           other.filter { $0.pid == previousPID }, music] {
            if let previous = candidates.first(where: { $0.pid == previousPID }) { return previous }
            if let current = candidates.first(where: { $0.pid == systemPID }) { return current }
            if let first = candidates.sorted(by: { $0.pid < $1.pid }).first { return first }
        }
        return includeOtherPlayers ? available.first { $0.pid == systemPID } : nil
    }
}
