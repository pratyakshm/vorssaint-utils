// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The command bar's face: one field, one list. Reads top to bottom with no
/// chrome to learn; every row is icon, name in plain words, where it lives,
/// and its shortcut so the bar teaches the faster way while being used.
struct CommandBarView: View {
    /// Short enough to sit on one line, chosen to show three different things
    /// the bar can do that a list of commands would never reveal.
    ///
    /// The battery one is the localized word, because that is the word the
    /// answer is titled with. As a fixed English "battery" the chip matched
    /// nothing in the other twelve languages and led to an empty list, which
    /// teaches the opposite of what an example is for. The other three hold
    /// everywhere: the maths is language-free, the conversion parser already
    /// takes each language's own word for "to", and the emoji names come from
    /// Unicode, which spells them in English on purpose.
    static func examples(_ text: CommandBarFeatureStrings) -> [String] {
        var examples = ["100 km to mi", "2+2*3"]
        if PowerSampler.hasInternalBattery {
            examples.append(text.answerBatteryLabel.lowercased())
        }
        examples.append("fire")
        return examples
    }
    /// As tall as the list is ever allowed to be, so the panel never grows
    /// past what a laptop screen can show above the fold.
    static let listCeiling: CGFloat = 420
    static let width: CGFloat = 560
    /// The window panel's own width: TinyCast's panel measures 750 points,
    /// and the command bar copies that width. The island and droplet copies
    /// keep the compact width above.
    static let windowWidth: CGFloat = 750
    /// The window panel's outer corner, again TinyCast's own panel radius.
    static let panelRadius: CGFloat = 26
    /// A floating actions menu's fixed width, so filtering its rows never
    /// moves it under the pointer.
    static let actionsWidth: CGFloat = 320
    /// One actions row's stated height, so the capped list lands on a row.
    static let actionsRowHeight: CGFloat = 36
    /// The field alone, as the compact bar shows it.
    static let fieldHeight: CGFloat = 44
    private static let homeChipID = "category.all"

    /// Where this copy is drawn: the island's own, or the bar's window, which
    /// follows how the bar was presented.
    var presentation: CommandBarPresentation? = nil

    @ObservedObject private var service = CommandBarService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var uninstaller = AppUninstaller.shared
    @ObservedObject private var homebrew = HomebrewManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @FocusState private var actionSearchFocused: Bool
    @State private var showHomebrewDetails = false
    /// TinyCast's minimal look: single-line rows with a trailing kind label,
    /// no chips, examples, badges or footer. Off restores the old chrome.
    @AppStorage(DefaultsKey.commandBarMinimalLook) private var minimalLook = true
    /// What the floating actions menu is filtered to. Local, never the
    /// search: typing there must not disturb the list behind the menu.
    @State private var actionFilter = ""

    /// The mark, made a handle. Dragging rides on AppKit's own window
    /// dragging — the same machinery a title bar uses — rather than a
    /// SwiftUI gesture, whose translation is read in a coordinate space
    /// that moves with the window and jitters under its own feet.
    private struct DragHandle: NSViewRepresentable {
        func makeNSView(context: Context) -> HandleView { HandleView() }
        func updateNSView(_ view: HandleView, context: Context) {}

        final class HandleView: NSView {
            private var moveObserver: NSObjectProtocol?
            private var saveTask: DispatchWorkItem?

            deinit {
                saveTask?.cancel()
                if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
            }

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

            override func resetCursorRects() {
                // Cursor rects, not a pushed NSCursor: the system hands the
                // arrow back on its own the moment the pointer leaves, even
                // if the bar hides mid-hover.
                addCursorRect(bounds, cursor: .openHand)
            }

            override func mouseDown(with event: NSEvent) {
                if event.clickCount == 2 {
                    CommandBarService.shared.resetPanelPosition()
                    return
                }
                guard let window else { return }
                NSCursor.closedHand.set()
                observeMovement(of: window)
                window.performDrag(with: event)
                scheduleSave()
                NSCursor.openHand.set()
            }

            private func observeMovement(of window: NSWindow) {
                saveTask?.cancel()
                if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
                moveObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.scheduleSave()
                }
            }

            private func scheduleSave() {
                saveTask?.cancel()
                let task = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
                    moveObserver = nil
                    saveTask = nil
                    CommandBarService.shared.finishPanelDrag()
                }
                saveTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
            }
        }
    }

    private var markTint: Color {
        colorScheme == .light ? Color(white: 0.03) : .white
    }

    private var text: CommandBarFeatureStrings { FeatureStrings.commandBar(l10n.language) }

    private var shownAs: CommandBarPresentation { presentation ?? service.presentation }

    /// The window copy is wide; the island and droplet copies keep the
    /// compact width the island's geometry is built around.
    private var panelWidth: CGFloat { shownAs == .window ? Self.windowWidth : Self.width }

    /// Out of the island the bar is the island's: black, or the open island's
    /// own surface, and dark like it.
    @ViewBuilder private var backdrop: some View {
        switch shownAs {
        case .window: HUDBackdrop(cornerRadius: Self.panelRadius, contrast: .high)
        case .droplet: RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black)
        case .island: Color.clear
        }
    }

    var body: some View {
        // Top-anchored: the menu floats over the list's corner while the
        // field stays exactly where it was, whatever the menu measures.
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                searchBar
                if let warning = service.uninstallWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 17)
                        .padding(.bottom, 12)
                }
                switch service.mode {
                case .search:
                    if showsCategoryChips {
                        Divider()
                        categoryChipsRow
                    }
                    if service.rows.isEmpty {
                        // A category with nothing in it needs the same way out a
                        // fruitless search gets, or the panel is a room with no
                        // door in it.
                        if !trimmedQuery.isEmpty || service.activeCategory != nil {
                            Divider()
                            emptyState
                        }
                    } else {
                        if !showsCategoryChips { Divider() }
                        resultsList
                    }
                case .argument(let entryID):
                    Divider()
                    argumentCard(entryID: entryID)
                case .confirm(let entryID):
                    Divider()
                    confirmCard(entryID: entryID)
                case .uninstallReview:
                    Divider()
                    uninstallReviewCard
                case .uninstallHomebrewConfirm:
                    Divider()
                    uninstallHomebrewConfirmCard
                case .actions:
                    // The list stays up behind the floating menu, the way a
                    // popover keeps its parent visible instead of replacing it.
                    if !service.rows.isEmpty {
                        Divider()
                        resultsList
                    }
                case .naming(let entryID):
                    Divider()
                    namingCard(entryID: entryID)
                case .capturingShortcut(let entryID):
                    Divider()
                    shortcutCard(entryID: entryID)
                }
                // A footer under a bare field reads as a second row of chrome on
                // something meant to be one strip. The minimal look swaps the
                // hint line for floating controls: a menu circle and pills.
                if !service.isCompactHome {
                    if minimalLook {
                        bottomBar
                    } else {
                        Divider()
                        footer
                    }
                }
            }
            .frame(width: panelWidth)
            .environment(\.colorScheme, shownAs == .window ? colorScheme : .dark)
            .background(backdrop)
            // The ⌘K menu floats over the list's own corner instead of
            // replacing it, so dismissing it lands back where it opened.
            // Hung under the header, never over it.
            if case .actions(let entryID) = service.mode, shownAs == .window {
                actionsPanel(entryID: entryID)
                    .padding(.trailing, 12)
                    .padding(.top, 64)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: shownAs == .window ? Self.panelRadius : 22,
                                    style: .continuous))
        .onAppear {
            focusSearch()
            service.barDidAppear()
        }
        .onChange(of: service.presentationID) { _, _ in focusSearch() }
        .onChange(of: service.mode) { _, mode in
            if case .actions = mode {
                actionFilter = ""
            } else {
                focusSearch()
            }
        }
        // Typing as the drop still falls hurries it, so the bar shows what
        // is being typed right away.
        .onChange(of: service.query) { _, query in
            if !query.isEmpty, service.presentation == .droplet { CommandBarDroplet.shared.hurry() }
        }
    }

    /// Only the copy on screen asks for the keyboard: a hidden copy taking it
    /// would hand its own empty text back to the search.
    private var isShown: Bool {
        presentation == .island ? service.presentation == .island : service.presentation != .island
    }

    /// While the actions menu is up the list behind it is frozen: a scroll
    /// under the pointer must not move the row the menu acts on.
    private var isActionsOpen: Bool {
        if case .actions = service.mode { return true }
        return false
    }

    private func focusSearch() {
        DispatchQueue.main.async { if isShown { searchFocused = true } }
    }

    // MARK: - Field

    private var searchBar: some View {
        HStack(spacing: 12) {
            // A magnifier leads the field, the way launchers do: the mark
            // stays on the quick panel and the radial menu, not here.
            // Both axes are pinned: the panel re-fits on every keystroke and
            // a glyph left to follow the proposed height shrinks or vanishes
            // mid-layout. It is also the handle that carries the bar to
            // wherever the hand wants it; a double-click brings it home.
            if shownAs == .window {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .allowsHitTesting(false)
                    .overlay(
                        DragHandle()
                            .help(text.dragHint)
                    )
            } else {
                // Out of the island, the companion is the bar's face, and the
                // bar stays where the island put it.
                CommandBarMascot(service: service)
                    .frame(width: 22, height: 22)
            }
            if case .naming(let entryID) = service.mode,
               let entry = service.entry(withID: entryID) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
            if case .argument(let entryID) = service.mode,
               let entry = service.entry(withID: entryID) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
            TextField(fieldPlaceholder, text: $service.query)
                .textFieldStyle(.plain)
                .font(.system(size: shownAs == .window ? 20 : 16))
                .focused($searchFocused)
                .disableAutocorrection(true)
                .accessibilityLabel(text.pageTitle)
            if service.isCompactHome, !minimalLook { compactHints }
            if !service.query.isEmpty {
                Button {
                    service.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    /// The collapsed bar has no footer, so the keys that still work (↓ to
    /// peek, Esc to close) say so inline instead, in the footer's own glyphs.
    private var compactHints: some View {
        HStack(spacing: 4) {
            Text("↓")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
            Text(text.suggestionsLabel)
                .font(.system(size: 9))
            Text("Esc")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.leading, 4)
        }
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .fixedSize()
    }

    /// Everything that can be done to the selected row, floating over the
    /// list's own corner instead of replacing it, so closing it lands back
    /// where it opened. A filter at its foot narrows the rows in place.
    private func actionsPanel(entryID: String) -> some View {
        let actions = service.actionRows
        let selectedID = actions.indices.contains(service.actionIndex)
            ? actions[service.actionIndex].id : nil
        let shown = filteredActions(actions)
        return VStack(spacing: 0) {
            if let entry = service.entry(withID: entryID) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, action in
                            if index > 0, actionsDividerAbove(action, after: shown[index - 1]) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.10))
                                    .frame(height: 1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            }
                            Button {
                                service.runAction(action)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: action.symbolName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(action.isDestructive
                                                         ? Color.red : Color.secondary)
                                        .frame(width: 20, height: 20)
                                    Text(action.title)
                                        .font(.body)
                                        .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    if action.id == selectedID {
                                        keyCap("↵")
                                    }
                                }
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, minHeight: Self.actionsRowHeight,
                                       maxHeight: Self.actionsRowHeight, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(action.id == selectedID
                                              ? Color.primary.opacity(0.10) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(action.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: (Self.actionsRowHeight + 1) * 5.5)
                .onChange(of: service.actionIndex) { _, _ in
                    if let selectedID { proxy.scrollTo(selectedID) }
                }
            }
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
            // The same bottom filter the launchers this copies put under
            // their own menus.
            TextField(text.actionsSearchPlaceholder, text: $actionFilter)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($actionSearchFocused)
                .disableAutocorrection(true)
                .padding(.horizontal, 20)
                .frame(height: Self.actionsRowHeight)
        }
        .frame(width: Self.actionsWidth)
        .background(HUDBackdrop(cornerRadius: 16, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .onAppear { actionSearchFocused = true }
    }

    /// The rows the filter keeps, in order. Empty shows everything, so
    /// clearing it is the way back.
    private func filteredActions(_ actions: [CommandBarService.RowAction]) -> [CommandBarService.RowAction] {
        let needle = actionFilter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return actions }
        return actions.filter { $0.title.localizedCaseInsensitiveContains(needle) }
    }

    /// A hairline above the housekeeping group and above a newly
    /// destructive run, so one list reads as sections, not a wall.
    private func actionsDividerAbove(_ action: CommandBarService.RowAction,
                                     after prev: CommandBarService.RowAction) -> Bool {
        if action.id == "pin", prev.id != "pin" { return true }
        return action.isDestructive && !prev.isDestructive
    }

    /// One outlined keycap for a row's chord, the way launchers draw theirs.
    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.20), lineWidth: 1)
            )
    }

    /// Naming a row: the field becomes the name, and says so when the name is
    /// already taken instead of quietly stealing it.
    private func namingCard(entryID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(service.aliasWarning ?? text.argumentHint)
                .font(.system(size: 10.5))
                .foregroundStyle(service.aliasWarning == nil
                                 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    /// Listening for the combination one row should answer to. The card says
    /// so plainly, because a field that silently swallows every key is the
    /// most confusing thing a panel can do.
    private func shortcutCard(entryID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if let existing = service.rowShortcut(for: entry) {
                        Text(existing.displayString)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(service.aliasWarning ?? text.shortcutCaptureHint)
                .font(.system(size: 10.5))
                .foregroundStyle(service.aliasWarning == nil
                                 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    private var fieldPlaceholder: String {
        if case .argument(let entryID) = service.mode,
           let range = service.entry(withID: entryID)?.numericRange {
            return String(format: text.argumentRangeFormat, range.lowerBound, range.upperBound)
        }
        if case .naming = service.mode { return text.aliasPlaceholder }
        return text.searchPlaceholder
    }

    // MARK: - Results

    private var trimmedQuery: String {
        service.query.trimmingCharacters(in: .whitespaces)
    }

    /// The chips stay up while a category is on, typing or not: a filter the
    /// person cannot see is a filter they will blame the bar for. The minimal
    /// look hides them outright; the category still clears with Esc.
    private var showsCategoryChips: Bool {
        !minimalLook && !service.categoryChips.isEmpty
            && (service.isShowingSuggestions || service.activeCategory != nil)
    }

    /// The categories, one tap deep: the same drill-in the launchers people
    /// know. "All" is home; Esc always walks back to it.
    private var categoryChipsRow: some View {
        ScrollViewReader { chips in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    categoryChip(nil, label: text.categoryAll)
                        .id(Self.homeChipID)
                    ForEach(service.categoryChips, id: \.self) { source in
                        categoryChip(source, label: service.categoryTitle(source))
                            .id(source.rawValue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .onChange(of: service.activeCategory) { _, category in
                // The arrow keys can walk past the edge of the row.
                withAnimation(.easeOut(duration: 0.12)) {
                    chips.scrollTo(category?.rawValue ?? Self.homeChipID)
                }
            }
        }
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.isShowingSuggestions, service.activeCategory == nil, !minimalLook {
                // A list of commands never says the bar can add up, convert or
                // reach into another app's menus. Examples do, and clicking
                // one fills the field so it can be tried on the spot.
                HStack(spacing: 5) {
                    Text(text.tryTheseLabel)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                    ForEach(CommandBarView.examples(text), id: \.self) { example in
                        Button {
                            service.query = example
                        } label: {
                            Text(example)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            ScrollViewReader { proxy in
                // The bar shows more than fits when nothing is typed, and a
                // list with no scrollbar looks like a list that ends there.
                ScrollView(showsIndicators: service.rows.count > 14) {
                    LazyVStack(spacing: minimalLook ? 0 : 1) {
                        ForEach(Array(service.rows.enumerated()), id: \.element.id) { index, entry in
                            // Every heading lives in the list, directly above
                            // the rows it names.
                            if let heading = service.sectionTitles[index] {
                                sectionHeader(heading)
                            }
                            row(entry, index: index)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                // A short list makes the panel exactly as tall as it needs to
                // be. A long one is pinned to its ceiling instead: asking the
                // layout for the ideal height of a hundred rows would measure
                // every one of them and throw the laziness away.
                .frame(maxHeight: Self.listCeiling)
                .fixedSize(horizontal: false, vertical: service.rows.count <= 14)
                .frame(minHeight: service.rows.count > 14 ? Self.listCeiling : nil)
                .onChange(of: service.selectedIndex) { _, index in
                    guard service.rows.indices.contains(index) else { return }
                    proxy.scrollTo(service.rows[index].id)
                }
            }
        }
    }

    private func categoryChip(_ source: CommandBarSource?, label: String) -> some View {
        let isActive = service.activeCategory == source
        return Button {
            service.setCategory(source)
        } label: {
            HStack(spacing: 3) {
                if let source {
                    Image(systemName: source.symbolName)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
            }
            // Tinted, never filled: white on a pale accent (yellow, orange in
            // light appearance) leaves the label invisible, and every other
            // selected surface in the panel is already accent at low opacity.
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(isActive
                                       ? Color.accentColor.opacity(0.18)
                                       : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(isActive ? 0.45 : 0),
                                            lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    /// One section's label, in its own case and weight: a heading names the
    /// rows under it instead of shouting over them.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func row(_ entry: CommandBarEntry, index: Int) -> some View {
        let isSelected = index == service.selectedIndex
        return Button {
            // By identity, not by position: a background load can rebuild the
            // list between the click and this call.
            service.run(entry, fromClick: true)
        } label: {
            HStack(spacing: 10) {
                iconView(entry)
                if minimalLook {
                    // One line: the name, its bound keys, then what it is on
                    // the right. Holding ⌘ turns the right side into the
                    // digit that runs the row. Any warning takes the right
                    // side instead of a kind label.
                    titleView(entry)
                    if let caps = rowKeyCaps(entry) {
                        HStack(spacing: 2) {
                            ForEach(caps, id: \.self) { cap in
                                keyCap(cap)
                            }
                        }
                    }
                    Spacer(minLength: 12)
                    if entry.trouble != nil {
                        subtitleView(entry)
                    } else if let value = entry.answerValue {
                        Text(value)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .monospacedDigit()
                    } else if service.commandIsHeld, index < 9 {
                        HStack(spacing: 2) {
                            keyCap("⌘")
                            keyCap("\(index + 1)")
                        }
                    } else if !entry.subtitle.isEmpty {
                        Text(entry.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1.5) {
                        titleView(entry)
                        subtitleView(entry)
                    }
                    Spacer(minLength: 12)
                    if service.commandIsHeld, index < 9 {
                        // Holding Command turns the list into nine numbered rows.
                        Text("⌘\(index + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    } else if let value = entry.answerValue {
                        Text(value)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .monospacedDigit()
                    } else if let shortcut = service.rowShortcut(for: entry)?.displayString
                                ?? entry.shortcut?.displayString ?? entry.menuShortcut {
                        Text(shortcut)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        // Always laid out, only drawn on the selected row: without
                        // the reserved width every row shifted as the selection
                        // moved.
                        .opacity(isSelected ? 1 : 0)
                }
            }
            .padding(.horizontal, minimalLook ? 8 : 9)
            .padding(.vertical, entry.isAnswer ? 9 : (minimalLook ? 6 : 7))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowFill(isSelected: isSelected))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering, !isActionsOpen { service.selectFromHover(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(entry))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The row's bound combination as single caps, or nil when no chord
    /// runs it: a row shortcut first, then the row's own, then someone
    /// else's menu shortcut written out as one cap.
    private func rowKeyCaps(_ entry: CommandBarEntry) -> [String]? {
        if let shortcut = service.rowShortcut(for: entry) ?? entry.shortcut {
            return shortcut.keyCaps
        }
        if let menu = entry.menuShortcut { return [menu] }
        return nil
    }

    /// The selection is a neutral wash, the same in every list, never the
    /// accent: a blue row reads as a button about to be pressed.
    private func rowFill(isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return minimalLook ? Color.primary.opacity(0.10) : Color.accentColor.opacity(0.14)
    }

    /// Everything the eye gets from a row, said in words: the name, where it
    /// lives, its value or shortcut, and the states that are only a colour.
    private func accessibilityLabel(_ entry: CommandBarEntry) -> String {
        var parts = [entry.title, entry.subtitle]
        if let value = entry.answerValue { parts.append(value) }
        if let shortcut = service.rowShortcut(for: entry)?.displayString
            ?? entry.shortcut?.displayString ?? entry.menuShortcut { parts.append(shortcut) }
        if entry.isActive { parts.append(text.stateOn) }
        if service.isPinned(entry) { parts.append(text.pinnedTitle) }
        switch entry.trouble {
        case .needsSetup(let feature, _): parts.append(String(format: text.needsSetupFormat, feature))
        case .needsPermission: parts.append(text.needsPermissionHint)
        case nil: break
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The title, plain: the row shows what it is, not why it matched.
    /// The calculator's result gets the loud treatment.
    @ViewBuilder
    private func titleView(_ entry: CommandBarEntry) -> some View {
        if entry.isAnswer {
            let font = Font.system(size: 17, weight: .semibold, design: .rounded)
            Text(entry.title)
                // Tabular digits keep a sum steady while typing; in a color
                // value they leave gaps between letters and digits.
                .font(entry.isColor ? font : font.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else if minimalLook {
            Text(entry.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(entry.title)
        } else {
            let offsets = service.highlightOffsets(for: entry)
            if offsets.isEmpty {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(entry.title)
            } else {
                Text(highlighted(entry.title, offsets: offsets))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func highlighted(_ title: String, offsets: Set<Int>) -> AttributedString {
        var result = AttributedString()
        for (index, character) in title.enumerated() {
            var piece = AttributedString(String(character))
            if offsets.contains(index) {
                piece.foregroundColor = Color.accentColor
                piece.font = .system(size: 13, weight: .bold)
            } else {
                piece.foregroundColor = .primary
            }
            result.append(piece)
        }
        return result
    }

    @ViewBuilder
    private func subtitleView(_ entry: CommandBarEntry) -> some View {
        switch entry.trouble {
        case .needsSetup(let featureTitle, _):
            Text(String(format: text.needsSetupFormat, featureTitle))
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .lineLimit(1)
        case .needsPermission:
            Text(text.needsPermissionHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.orange)
                .lineLimit(1)
        case nil:
            // A row under a heading that already names its area carries no
            // caption at all, which makes the browse list read as one column
            // of names instead of a wall of repetition.
            if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func iconView(_ entry: CommandBarEntry) -> some View {
        // The minimal look draws icons bare at one size, with no plate and
        // no badge: a dot under a running app says it runs.
        let side: CGFloat = minimalLook ? 26 : 30
        return ZStack(alignment: .topTrailing) {
            if minimalLook {
                iconContent(entry, side: side)
                    .frame(width: side, height: side)
            } else if entry.usesPlateIcon {
                // An app or file icon already has its own shape and padding, so a
                // plate behind it reads as a second frame; only glyphs get one.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(entry.isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06))
                    .frame(width: 30, height: 30)
                    .overlay(iconContent(entry, side: 30))
            } else {
                iconContent(entry, side: 30)
                    .frame(width: 30, height: 30)
            }
            if entry.isActive {
                if minimalLook {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 3, height: 3)
                        .offset(y: 3)
                } else {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                        // A ring keeps the dot legible on top of a colorful icon.
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.2))
                        .offset(x: 2.5, y: -2.5)
                }
            }
        }
    }

    @ViewBuilder
    private func iconContent(_ entry: CommandBarEntry, side: CGFloat = 30) -> some View {
        switch entry.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: minimalLook ? 14 : 13.5,
                              weight: minimalLook ? .medium : .semibold))
                .foregroundStyle(entry.isActive && !minimalLook
                                 ? Color.accentColor : Color.primary.opacity(0.85))
        case .appIcon(let path):
            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
        case .clipboardImage(let name):
            ClipboardThumbnailImage(source: .stored(name: name), contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .filePath(let path):
            Image(nsImage: CommandBarIconCache.icon(forPath: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
        case .color(let color):
            ColorSwatch(color: color, size: 22)
        }
    }

    // MARK: - Empty, argument and confirm states

    private var emptyState: some View {
        VStack(spacing: 9) {
            BrandMark(width: 26, tint: markTint)
                .opacity(0.3)
                .frame(width: 26, height: 26)
                .padding(.bottom, 2)
            Text(text.noResultsTitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                service.goHome()
            } label: {
                Text(text.noResultsAction)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func argumentCard(entryID: String) -> some View {
        VStack(spacing: 4) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 17)
                .padding(.top, 12)
            }
            Text(text.argumentHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
        }
    }

    private func confirmCard(entryID: String) -> some View {
        VStack(spacing: 6) {
            if let entry = service.entry(withID: entryID) {
                HStack(spacing: 10) {
                    iconView(entry)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(entry.confirmationPrompt ?? entry.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(text.confirmHint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Someone who opened the bar with the mouse has to be able
                    // to finish with the mouse.
                    Button(l10n.s.uninstallerCancel) { service.stepBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(text.confirmButton) {
                        service.runSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.09))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Uninstall review

    /// The full leftover-files checklist, in place for `.uninstallReview` -
    /// the same categories, sizes and per-item toggles `UninstallerView`
    /// shows in Settings, just inline in the bar. Homebrew-managed apps are
    /// handled here too, not handed off to Settings: `.uninstallHomebrewConfirm`
    /// guards the extra confirmation `brew uninstall` needs, and
    /// `HomebrewOperationStatusView` renders its live progress inline.
    @ViewBuilder
    private var uninstallReviewCard: some View {
        switch uninstaller.phase {
        case .empty:
            VStack(spacing: 12) {
                Text(l10n.s.uninstallerSelectionUnavailable)
                    .foregroundStyle(.secondary)
                Button(l10n.s.uninstallerCancel) { service.stepBack() }
            }
            .padding(20)
        case .scanning:
            uninstallReviewBusy(l10n.s.uninstallerScanning)
        case .results:
            uninstallReviewChecklist
        case .removing:
            uninstallReviewBusy(l10n.s.uninstallerRemoving)
        case let .done(freed, failed):
            uninstallReviewDone(freed: freed, failed: failed)
        }
    }

    private func uninstallReviewBusy(_ message: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let target = uninstaller.target {
                HStack(spacing: 7) {
                    Image(nsImage: target.icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(target.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var uninstallReviewChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            uninstallReviewHeader
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(AppUninstaller.Category.allCases, id: \.self) { category in
                        let group = uninstaller.items.filter { $0.category == category }
                        if !group.isEmpty {
                            uninstallCategoryGroup(group, category: category)
                        }
                    }
                }
                .padding(.horizontal, 17)
            }
            .frame(maxHeight: Self.listCeiling - 90)
            Divider().padding(.horizontal, 17)
            uninstallHomebrewStatus
            uninstallReviewFooter
        }
        .padding(.vertical, 12)
    }

    /// Live progress for a Homebrew-managed app's removal, shown inline once
    /// confirmed - the same view the menu panel already shows in its own
    /// small floating window, so nothing here is rebuilt from scratch.
    @ViewBuilder
    private var uninstallHomebrewStatus: some View {
        if let package = uninstaller.selectedHomebrewPackage {
            if let status = homebrew.operationStatus,
               status.action == .uninstall,
               status.package?.id == package.id {
                HomebrewOperationStatusView(status: status,
                                            log: homebrew.log,
                                            terminalFallbackCommand: homebrew.terminalFallbackCommand,
                                            compact: true,
                                            showDetails: $showHomebrewDetails,
                                            onCancel: homebrew.cancelOperation,
                                            onClear: homebrew.clearLog,
                                            onOpenTerminal: homebrew.openTerminalFallback)
                    .padding(.horizontal, 17)
                if let tap = homebrew.untrustedTap {
                    HomebrewTrustCard(tap: tap, compact: true)
                        .padding(.horizontal, 17)
                }
                if let error = homebrew.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 17)
                }
            } else {
                Label(String(format: l10n.s.uninstallerHomebrewPackageFormat, package.displayName),
                      systemImage: "shippingbox")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 17)
            }
            Divider().padding(.horizontal, 17)
        }
    }

    private var uninstallReviewHeader: some View {
        HStack(spacing: 9) {
            if let target = uninstaller.target {
                Image(nsImage: target.icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(target.bundleID ?? target.url.path)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Self.uninstallByteString(uninstaller.totalSize))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(l10n.s.uninstallerFoundTitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 17)
    }

    private func uninstallCategoryGroup(_ group: [AppUninstaller.Leftover],
                                        category: AppUninstaller.Category) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(uninstallCategoryLabel(category).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            ForEach(group) { item in
                uninstallReviewRow(item)
            }
        }
    }

    private func uninstallReviewRow(_ item: AppUninstaller.Leftover) -> some View {
        HStack(spacing: 7) {
            Toggle(item.name, isOn: uninstallIncludeBinding(item))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .focusable(interactions: .edit)
                .onKeyPress(.space) {
                    let included = uninstaller.items.first(where: { $0.id == item.id })?.include ?? false
                    uninstaller.setInclude(!included, for: item.id)
                    return .handled
                }
                .disabled(uninstaller.isRemoving)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    if item.confidence == .related {
                        Label(l10n.s.cleanerOptionalSection, systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                    Text(item.url.deletingLastPathComponent().path
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .font(.system(size: 9.5))
            }
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help(l10n.s.cleanerRevealInFinder)
            .accessibilityLabel(l10n.s.cleanerRevealInFinder)
            Text(Self.uninstallByteString(item.size))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 22)
    }

    private var uninstallReviewFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: l10n.s.uninstallerSelectedFormat,
                            uninstaller.items.filter(\.include).count, uninstaller.items.count))
                    .font(.system(size: 11, weight: .medium))
                Text(Self.uninstallByteString(uninstaller.selectedSize))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(l10n.s.uninstallerCancel) { service.stepBack() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button {
                service.runSelected()
            } label: {
                Label(uninstaller.selectedHomebrewPackage == nil
                      ? l10n.s.uninstallerRemove : l10n.s.homebrewUninstall,
                      systemImage: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .disabled(!uninstaller.items.contains(where: \.include)
                      || (uninstaller.selectedHomebrewPackage != nil && homebrew.isBusy))
        }
        .padding(.horizontal, 17)
    }

    private func uninstallReviewDone(freed: Int64, failed: [AppUninstaller.Leftover]) -> some View {
        VStack(spacing: 9) {
            Image(systemName: UninstallerSupport.doneSymbol(hasLeftovers: !failed.isEmpty))
                .font(.system(size: 28))
                .foregroundStyle(failed.isEmpty ? .green : .orange)
            Text(l10n.s.uninstallerDoneTitle)
                .font(.system(size: 13, weight: .bold))
            Text(String(format: l10n.s.uninstallerFreedFormat, Self.uninstallByteString(freed)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !failed.isEmpty {
                UninstallFailureNote(items: failed, compact: true)
                    .padding(.horizontal, 17)
            }
            Button(l10n.s.uninstallerAnother) { service.runSelected() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private func uninstallIncludeBinding(_ item: AppUninstaller.Leftover) -> Binding<Bool> {
        Binding(
            get: { uninstaller.items.first(where: { $0.id == item.id })?.include ?? false },
            set: { uninstaller.setInclude($0, for: item.id) }
        )
    }

    private func uninstallCategoryLabel(_ category: AppUninstaller.Category) -> String {
        switch category {
        case .app: return l10n.s.uninstallerCatApp
        case .support: return l10n.s.uninstallerCatSupport
        case .caches: return l10n.s.uninstallerCatCaches
        case .preferences: return l10n.s.uninstallerCatPreferences
        case .containers: return l10n.s.uninstallerCatContainers
        case .logs: return l10n.s.uninstallerCatLogs
        case .state: return l10n.s.uninstallerCatState
        case .other: return l10n.s.uninstallerCatOther
        }
    }

    private static func uninstallByteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Guards a Homebrew-managed app's removal, the same extra step the
    /// Settings page and menu panel already ask for before running `brew
    /// uninstall` - styled like `confirmCard` since it is the same kind of
    /// destructive guard, just reached from the checklist instead of a row.
    private var uninstallHomebrewConfirmCard: some View {
        VStack(spacing: 6) {
            if let target = uninstaller.target, let package = uninstaller.selectedHomebrewPackage {
                HStack(spacing: 10) {
                    Image(nsImage: target.icon)
                        .resizable()
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(l10n.s.homebrewConfirmUninstallTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(String(format: l10n.s.homebrewConfirmUninstallBodyFormat, package.displayName))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(l10n.s.uninstallerCancel) { service.stepBack() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(l10n.s.homebrewUninstall) { service.runSelected() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.red)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.09))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Footer

    /// Floating controls instead of a hint line: the menu circle on the
    /// left, the action pills on the right. No bar, just controls.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                CommandBarService.shared.hide()
                SettingsRouter.shared.page = .commandBar
                appDelegate()?.openSettingsWindow()
            } label: {
                BrandMark(width: 14, tint: markTint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(text.actionOpenSettings)
            Spacer(minLength: 0)
            // The pills advertise exactly what the keys do: ⌘K toggles this
            // row's menu, so the pill stays up while the menu is open.
            if service.canOpenActions || isActionsOpen {
                Button {
                    if isActionsOpen { service.stepBack() } else { service.openActions() }
                } label: {
                    HStack(spacing: 6) {
                        Text(text.actionsHint)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        keyCap("⌘")
                        keyCap("K")
                    }
                    .padding(4)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Text(GlobalShortcut.saved(for: DefaultsKey.commandBarShortcut,
                                      fallback: .commandBarDefault).displayString)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            if service.canOpenActions {
                Text("⌘K")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(text.actionsHint)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
            }
            Text(service.isShowingSuggestions && !service.categoryChips.isEmpty ? "⌃P ⌃N ↑↓ ←→" : "⌃P ⌃N ↑↓")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            if service.selectedEntry?.id == "math.result" {
                Text("⇥")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(text.reuseHint)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "return")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text("Esc")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// App and file icons resolved once and kept; NSWorkspace re-reads them from
/// disk on every call otherwise, once per row per render.
///
/// What it keeps is a small bitmap, not what the system hands over: a real
/// app icon carries every representation up to 1024 points, and a few hundred
/// of those held at full size would cost more memory than the rest of the app
/// put together. The rows draw at 28 points, so 64 pixels is already more
/// than any display needs.
enum CommandBarIconCache {
    private static let side: CGFloat = 64

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        // NSCache alone only sheds under system memory pressure, which is too
        // late; the cost ceiling keeps the whole set inside a few megabytes.
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let full = NSWorkspace.shared.icon(forFile: path)
        let small = downsampled(full)
        cache.setObject(small, forKey: path as NSString, cost: Int(side * side * 4))
        return small
    }

    private static func downsampled(_ image: NSImage) -> NSImage {
        let size = NSSize(width: side, height: side)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(side),
                                         pixelsHigh: Int(side),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0)
        else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero,
                   operation: .copy,
                   fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}

/// The companion as the bar's face: it glances about as you type, thinks
/// while answers load, hops when they arrive and looks lost when nothing
/// matches.
private struct CommandBarMascot: View {
    @ObservedObject var service: CommandBarService
    @State private var cue: NotchMascotCue?
    @State private var cueID = 0

    private var mood: NotchMascotMood {
        NotchMascotSupport.commandBarMood(query: service.query, hasResults: !service.rows.isEmpty,
                                          searching: service.awaitsAnswers)
    }

    var body: some View {
        NotchMascotView(look: NotchMascotSupport.look(), mood: mood, size: 22, cue: cue, cueID: cueID)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Its eyes go along what is typed, and come back once typing stops.
            .onChange(of: service.query) { _, query in
                cue = .look(NotchMascotSupport.readingGaze(for: query))
                cueID += 1
            }
            // After the look, so results arriving with a keystroke win.
            .onChange(of: mood) { old, new in
                guard NotchMascotSupport.celebrates(from: old, to: new, query: service.query,
                                                    hasResults: !service.rows.isEmpty) else { return }
                cue = .celebrate
                cueID += 1
            }
    }
}
