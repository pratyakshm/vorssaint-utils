// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The facts a primary-action pill needs, copied from a row at render time.
/// Deliberately free of the SwiftUI view, the service and the disk: the label
/// must stay computable in a test and cheap enough to build once per render.
struct CommandBarPrimaryActionRow {
    enum LinkKind {
        case link
        case place
        case script
    }

    let id: String
    let title: String
    let isAnswer: Bool
    let isColor: Bool
    let needsSetup: Bool
    let uninstallAppURL: URL?
    /// True when the row has a finished path to reveal. A saved place that
    /// still holds a placeholder has none until it runs.
    let hasRevealPath: Bool
    /// True when the row's reveal path is a folder, decided when the catalog
    /// built the row so drawing never asks the file system.
    let revealIsFolder: Bool
    let linkKind: LinkKind?
}

/// Names what Return does to the selected row. Each branch describes the
/// action, never the row's category: "Copy Color" for a color answer, "Run
/// Script" for a saved script, "Paste" for a clipboard item.
enum CommandBarPrimaryAction {
    static func title(for row: CommandBarPrimaryActionRow,
                      text: CommandBarFeatureStrings) -> String? {
        if row.needsSetup { return text.actionOpenSettings }
        if row.isAnswer {
            return row.isColor ? text.primaryCopyColor : text.primaryCopyAnswer
        }
        if row.id.hasPrefix("selection.uninstall") { return row.title }
        if row.uninstallAppURL != nil {
            return String(format: text.uninstallAppFormat, row.title)
        }
        // Navigation rows under the uninstaller share the prefix but open a
        // list or reveal a Finder selection. Their own title already says so.
        if row.id.hasPrefix("uninstall.") { return row.title }

        if row.id.hasPrefix("app.") { return text.primaryOpenApp }
        if row.id.hasPrefix("folder.") { return text.primaryOpenFolder }
        if row.id.hasPrefix("file.") {
            return row.revealIsFolder ? text.primaryOpenFolder : text.primaryOpenFile
        }
        if row.id == "emoji.browse" { return text.primaryOpenEmoji }
        if row.id.hasPrefix("emoji.") { return text.primaryInsertEmoji }
        if row.id.hasPrefix("clipboard.") { return L10n.shared.s.menuPaste }
        if row.id.hasPrefix("snippet.") { return text.kindSnippet }
        if row.id.hasPrefix("window.") { return text.primarySwitchWindow }
        if row.id.hasPrefix("kill.") { return text.primaryKillProcess }
        // A quit row's title is already the localized action, "Quit Mail".
        if row.id.hasPrefix("quit.") { return row.title }
        if row.id.hasPrefix("menu.") { return text.primaryRunMenuCommand }

        if row.id.hasPrefix("link."), let kind = row.linkKind {
            switch kind {
            case .script: return text.primaryRunScript
            case .link: return text.primaryOpenLink
            case .place:
                guard row.hasRevealPath else { return text.primaryRunCommand }
                return row.revealIsFolder ? text.primaryOpenFolder : text.primaryOpenFile
            }
        }

        if row.id == "action.openURL" { return text.openInBrowser }
        if row.id == "action.openSettings"
            || row.id.hasPrefix("settings.")
            || row.id.hasPrefix("macsettings.")
            || row.id == "action.cleaner"
            || row.id == "action.uninstaller" {
            return text.actionOpenSettings
        }

        if row.id == "selection.copy" { return text.selectionCopy }
        if row.id == "selection.search" { return text.selectionSearch }
        if row.id == "selection.upper" { return text.selectionUpper }
        if row.id == "selection.lower" { return text.selectionLower }
        if row.id == "selection.titleCase" { return text.selectionTitleCase }
        if row.id == "selection.shelf" { return text.selectionShelf }
        if row.id == "selection.count" { return text.selectionCount }
        if row.id == "selection.cleanLink" { return text.actionCleanURL }

        return text.primaryRunCommand
    }
}
