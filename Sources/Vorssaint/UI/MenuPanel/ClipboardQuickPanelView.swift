// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The clipboard history window, laid out like Tinycast's clipboard palette:
/// a fixed list column beside a preview, a floating header and footer, and
/// no chrome of their own behind either bar.
struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @State private var previewSelection = QuickPreviewSelection()
    @State private var editingEntryID: UUID?
    @State private var clearingIDs: [UUID: Date]?
    @State private var actionsPresented = false
    @State private var filterPresented = false
    @State private var appMenuPresented = false

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var filtered: [ClipboardHistoryEntry] {
        history.filteredQuickEntries
    }

    private var canReorderEntries: Bool {
        history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchTokens: [String] {
        ClipboardHistorySearch.searchTokens(for: history.quickQuery)
    }

    /// The row the Actions menu acts on: the one the preview follows, falling
    /// back to the keyboard selection when the preview is closed.
    private var actionsEntry: ClipboardHistoryEntry? {
        ClipboardHistorySelection.previewEntry(
            preferredID: history.quickPreviewPresented ? previewSelection.entryID : nil,
            visibleEntries: filtered,
            selectedEntry: history.selectedQuickEntry)
    }

    private var anyMenuPresented: Bool {
        actionsPresented || filterPresented || appMenuPresented
    }

    private var previewIsEditing: Bool {
        editingEntryID != nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                content
            }
            footer
            menuOverlays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                Rectangle().fill(PanelSurface.baseFill(for: colorScheme))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            previewSelection.select(history.selectedQuickEntryID)
            DispatchQueue.main.async { searchFocused = true }
        }
        .onDisappear {
            previewSelection.select(nil)
            editingEntryID = nil
            closeMenus()
        }
        .onChange(of: history.quickSelectionID) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickQuery) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickTypeFilter) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickWindowPresentationID) { _, _ in
            // The panel is only ordered out between uses, so the view's own
            // menu state survives a hide. A fresh open starts with no menu up.
            closeMenus()
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickActionsRequestID) { _, _ in
            guard let entry = actionsEntry else { return }
            history.selectQuickEntry(entry)
            previewSelection.select(entry.id)
            filterPresented = false
            appMenuPresented = false
            actionsPresented = true
            syncMenuState()
        }
        .onChange(of: history.quickMenuCloseRequestID) { _, _ in
            closeMenus()
        }
        .modifier(ClipboardClearRecentConfirmation(entryIDs: $clearingIDs))
    }

    private var header: some View {
        HStack(spacing: 0) {
            // The list's own 16pt inset, so the chevron lines up with its icons.
            gutter(DS.Space.large)
            ClipboardHeaderBackButton { history.hideHistoryWindow() }
                .help(l10n.s.menuClose)
                .accessibilityLabel(Text(l10n.s.actionBack))
            gutter(DS.Space.medium)
            searchField
            gutter(DS.Space.small)
            ClipboardFilterButton(
                filter: history.quickTypeFilter,
                isOpen: filterPresented,
                title: text.filterByType
            ) {
                filterPresented.toggle()
                actionsPresented = false
                appMenuPresented = false
                syncMenuState()
            }
            gutter(DS.Space.large)
        }
        .frame(height: DS.Size.headerHeight)
        .padding(.top, DS.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        TextField("", text: $history.quickQuery)
            .textFieldStyle(.plain)
            .font(DS.Font.searchField)
            .focused($searchFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(alignment: .leading) {
                if history.quickQuery.isEmpty {
                    Text(text.searchPrompt)
                        .font(DS.Font.searchField)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(Text(text.searchPrompt))
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState(history.entries.isEmpty ? text.empty : text.noResults)
        } else {
            HStack(spacing: 0) {
                ClipboardListColumn(
                    entries: filtered,
                    tokens: searchTokens,
                    canReorderEntries: canReorderEntries,
                    previewIsEditing: previewIsEditing,
                    language: l10n.language,
                    previewSelection: previewSelection
                )
                .frame(width: history.quickPreviewPresented ? DS.Size.clipboardListWidth : nil)
                if history.quickPreviewPresented {
                    Rectangle()
                        .fill(PanelSurface.border(for: colorScheme))
                        .frame(width: 1)
                    QuickPreviewPane(
                        text: text,
                        selection: previewSelection,
                        editingEntryID: $editingEntryID)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: DS.Space.medium) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(DS.Font.panelBody)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            ClipboardMenuCircleButton(title: text.menu) {
                appMenuPresented.toggle()
                actionsPresented = false
                filterPresented = false
                syncMenuState()
            }
            Spacer(minLength: 0)
            actionGroup
        }
        .padding(.horizontal, DS.Space.small)
        .frame(height: DS.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    private var actionGroup: some View {
        HStack(spacing: DS.Space.micro) {
            ClipboardBarButton(isEnabled: history.selectedQuickEntry != nil) {
                history.copySelectedQuickEntry()
            } label: {
                HStack(spacing: DS.Space.xSmall) {
                    Text(primaryActionTitle)
                        .font(DS.Font.bar)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    ClipboardKeyCap(text: "↵")
                }
            }
            ClipboardBarButton(isEnabled: actionsEntry != nil) {
                if let entry = actionsEntry {
                    history.selectQuickEntry(entry)
                    previewSelection.select(entry.id)
                }
                actionsPresented.toggle()
                filterPresented = false
                appMenuPresented = false
                syncMenuState()
            } label: {
                HStack(spacing: DS.Space.xSmall) {
                    Text(text.actions)
                        .font(DS.Font.bar)
                        .foregroundStyle(.secondary)
                    HStack(spacing: DS.Space.micro) {
                        ClipboardKeyCap(text: "⌘")
                        ClipboardKeyCap(text: "K")
                    }
                }
            }
        }
        .padding(DS.Space.xxSmall)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(
            Capsule().strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        )
    }

    private var primaryActionTitle: String {
        if history.quickBatchCount > 0 {
            return String(format: text.pasteSelectedFormat, history.quickBatchCount)
        }
        return "Paste to \(history.pasteTargetDisplayName ?? "App")"
    }

    @ViewBuilder
    private var menuOverlays: some View {
        if anyMenuPresented {
            // A popover's outside click, inside the panel: the first press
            // closes the menu instead of reaching a row under it.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeMenus() }
        }
        if filterPresented {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ClipboardFilterPopover(selection: $history.quickTypeFilter) {
                        filterPresented = false
                        syncMenuState()
                    }
                    .clipboardMenuSurface(width: DS.Size.clipboardFilterMenuWidth)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, DS.Size.headerHeight + DS.Size.headerPadding + DS.Space.small)
            .padding(.trailing, DS.Space.large)
        }
        if let entry = actionsEntry, actionsPresented {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ClipboardActionsPopover(
                        entry: entry,
                        canReorder: canReorderEntries,
                        dismiss: {
                            actionsPresented = false
                            syncMenuState()
                        },
                        onEdit: {
                            actionsPresented = false
                            syncMenuState()
                            if !history.quickPreviewPresented {
                                history.toggleQuickPreview()
                            }
                            history.selectQuickEntry(entry)
                            previewSelection.select(entry.id)
                            editingEntryID = entry.id
                            history.editingEntryID = entry.id
                        },
                        onCopyText: {
                            actionsPresented = false
                            syncMenuState()
                            ClipboardImageTextCopy.copyText(
                                for: entry, language: l10n.language)
                        },
                        onClearRecent: {
                            actionsPresented = false
                            syncMenuState()
                            clearingIDs = history.recentEntriesSnapshot
                        }
                    )
                    .clipboardMenuSurface(width: DS.Size.actionMenuWidth)
                }
            }
            .padding(.bottom, DS.Size.bottomBarHeight + DS.Space.small)
            .padding(.trailing, DS.Space.small)
        }
        if appMenuPresented {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ClipboardAppMenuPopover(
                        onTogglePreview: {
                            appMenuPresented = false
                            syncMenuState()
                            history.toggleQuickPreview()
                        },
                        onClearRecent: {
                            appMenuPresented = false
                            syncMenuState()
                            clearingIDs = history.recentEntriesSnapshot
                        },
                        onClose: {
                            appMenuPresented = false
                            syncMenuState()
                            history.hideHistoryWindow()
                        }
                    )
                    .clipboardMenuSurface(width: DS.Size.clipboardFilterMenuWidth)
                    Spacer(minLength: 0)
                }
            }
            .padding(.bottom, DS.Size.bottomBarHeight + DS.Space.small)
            .padding(.leading, DS.Space.small)
        }
    }

    private func gutter(_ width: CGFloat) -> some View {
        Color.clear.frame(width: width)
    }

    private func closeMenus() {
        actionsPresented = false
        filterPresented = false
        appMenuPresented = false
        syncMenuState()
    }

    /// The key monitor owns Escape, so it has to know a menu is up before it
    /// decides whether Escape closes a menu or the window.
    private func syncMenuState() {
        history.quickMenuIsOpen = anyMenuPresented
    }
}

/// The sidebar alone observes hover selection. Changing its entry never
/// invalidates the enclosing list.
private final class QuickPreviewSelection: ObservableObject {
    @Published private(set) var entryID: UUID?

    func select(_ id: UUID?) {
        guard entryID != id else { return }
        entryID = id
    }
}

private struct QuickPreviewPane: View {
    let text: ClipboardFeatureStrings
    @ObservedObject var selection: QuickPreviewSelection
    @Binding var editingEntryID: UUID?
    @ObservedObject private var history = ClipboardHistoryService.shared

    var body: some View {
        ClipboardEntryPreviewSidebar(
            text: text,
            entry: ClipboardHistorySelection.previewEntry(
                preferredID: selection.entryID,
                visibleEntries: history.filteredQuickEntries,
                selectedEntry: history.selectedQuickEntry),
            editingEntryID: $editingEntryID)
    }
}

/// The list column: a fixed 290pt lane of section headers and one-line rows.
/// No dividers; selection is a rounded fill, and search results have no headers.
private struct ClipboardListColumn: View {
    let entries: [ClipboardHistoryEntry]
    let tokens: [String]
    let canReorderEntries: Bool
    let previewIsEditing: Bool
    let language: AppLanguage
    let previewSelection: QuickPreviewSelection
    @ObservedObject private var history = ClipboardHistoryService.shared

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(language)
    }

    private var pinned: [ClipboardHistoryEntry] {
        entries.filter(\.isPinned)
    }

    private var bucketedRecents: [(offset: Int, bucket: ClipboardHistoryDateBucket,
                                   entries: [ClipboardHistoryEntry])] {
        ClipboardHistoryDateBucket.bucketed(entries.filter { !$0.isPinned }).enumerated().map {
            (offset: $0.offset, bucket: $0.element.bucket, entries: $0.element.entries)
        }
    }

    private var isSearching: Bool {
        !history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if entries.count <= Self.eagerRowLimit {
                        VStack(alignment: .leading, spacing: 0) { topAnchor; sections }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) { topAnchor; sections }
                    }
                }
                .padding(.horizontal, DS.Space.small)
                .padding(.bottom, DS.Space.small + DS.Size.bottomBarHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ScrollBounceDisabler())
            .onChange(of: history.quickSelectionID) { _, _ in scrollSelectedEntry(with: proxy) }
            .onChange(of: history.quickSelectionIsVisible) { _, _ in
                scrollSelectedEntry(with: proxy)
            }
            .onChange(of: history.quickQuery) { _, _ in scrollSelectedEntry(with: proxy) }
            .onChange(of: history.quickTypeFilter) { _, _ in scrollSelectedEntry(with: proxy) }
            // The window is only hidden between uses, so without this it
            // reopens wherever it was scrolled, while the selection and
            // ⌘1 to ⌘9 already start from the first entries.
            .onChange(of: history.quickWindowPresentationID) { _, _ in
                proxy.scrollTo(Self.topAnchorID, anchor: .top)
            }
        }
    }

    /// Emits the headers and rows straight into the enclosing stack. If
    /// wrapped, the whole section becomes one lazy unit and builds every entry.
    private static let eagerRowLimit = 300

    /// The list's top inset, above the first section's header that scrolling
    /// to the first row would leave cut off. Scrolling it into place lands
    /// exactly where a first open starts.
    private static let topAnchorID = "clipboard-list-top"

    private var topAnchor: some View {
        Color.clear
            .frame(height: DS.Space.xxSmall)
            .id(Self.topAnchorID)
    }

    @ViewBuilder
    private var sections: some View {
        if isSearching {
            rows(title: nil, entries: entries, isFirst: true)
        } else {
            rows(title: text.pinned, entries: pinned, isFirst: true)
            ForEach(bucketedRecents, id: \.offset) { group in
                rows(title: group.bucket.title, entries: group.entries,
                     isFirst: pinned.isEmpty && group.offset == 0)
            }
        }
    }

    @ViewBuilder
    private func rows(title: String?, entries: [ClipboardHistoryEntry],
                      isFirst: Bool = false) -> some View {
        if !entries.isEmpty {
            if let title {
                Text(title)
                    .font(DS.Font.sectionHeader)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, DS.Space.small)
                    .padding(.top, isFirst ? DS.Space.xxSmall : DS.Space.medium)
                    .padding(.bottom, DS.Space.xxSmall)
            }
            ForEach(entries, id: \.id) { entry in
                ClipboardRowView(
                    entry: entry,
                    tokens: tokens,
                    shortcutIndex: shortcutIndex(for: entry),
                    isSelected: history.selectedQuickEntryID == entry.id,
                    isBatchSelected: history.isQuickBatchSelected(entry),
                    canReorderEntries: canReorderEntries,
                    previewIsEditing: previewIsEditing,
                    presentationID: history.quickWindowPresentationID,
                    language: language,
                    previewSelection: previewSelection
                )
                .equatable()
                .id(entry.id)
            }
        }
    }

    private func shortcutIndex(for entry: ClipboardHistoryEntry) -> Int? {
        entries.prefix(9).firstIndex(where: { $0.id == entry.id })
    }

    private func scrollSelectedEntry(with proxy: ScrollViewProxy) {
        guard history.quickSelectionIsVisible, let id = history.selectedQuickEntryID else { return }
        // No anchor and no animation: the list moves only when the selected
        // row is off screen, and then straight to it, so every arrow press
        // costs the same and the rows never redraw mid-slide.
        proxy.scrollTo(id)
    }
}

/// One entry as a list row. Keep hover within it so moving the pointer does
/// not rebuild the others. Value inputs let SwiftUI skip entries unaffected
/// by selection or history changes.
private struct ClipboardRowView: View, Equatable {
    let entry: ClipboardHistoryEntry
    let tokens: [String]
    let shortcutIndex: Int?
    let isSelected: Bool
    let isBatchSelected: Bool
    let canReorderEntries: Bool
    let previewIsEditing: Bool
    let presentationID: UUID
    let language: AppLanguage
    let previewSelection: QuickPreviewSelection
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    /// The pane follows a row only once the pointer has rested on it: while
    /// rows stream under a still pointer during a scroll, every one of them
    /// would otherwise redraw the pane, and a long entry costs a frame or two
    /// each time.
    @State private var previewFollowTask: Task<Void, Never>?
    private static let previewFollowDelay: Duration = .milliseconds(120)

    private var history: ClipboardHistoryService { .shared }
    private var l10n: L10n { .shared }
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(language) }

    // Preview selection is a channel to the sidebar, not part of this row's
    // appearance, so it stays out of the comparison.
    static func == (lhs: ClipboardRowView, rhs: ClipboardRowView) -> Bool {
        lhs.entry == rhs.entry
            && lhs.tokens == rhs.tokens
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.isSelected == rhs.isSelected
            && lhs.isBatchSelected == rhs.isBatchSelected
            && lhs.canReorderEntries == rhs.canReorderEntries
            && lhs.previewIsEditing == rhs.previewIsEditing
            && lhs.presentationID == rhs.presentationID
            && lhs.language == rhs.language
            && lhs.colorScheme == rhs.colorScheme
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.rowIconGap) {
            icon
                .frame(width: DS.Size.resultRowIcon, height: DS.Size.resultRowIcon)
            SearchHighlightText.text(previewText, tokens: tokens, fontSize: DS.Font.bodySize)
                .font(DS.Font.body)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, DS.Space.small)
        .padding(.vertical, DS.Space.xSmall)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(fill)
        )
        .contentShape(Rectangle())
        .contextMenu { entryActions(entry) }
        .onHover { hovering in
            // A row arriving under a pointer that has not moved since the
            // arrow keys took over is not a hover.
            if hovering, NSEvent.mouseLocation == history.keyboardSelectionPointer { return }
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
            previewFollowTask?.cancel()
            guard hovering, !previewIsEditing else { return }
            let id = entry.id
            previewFollowTask = Task { @MainActor in
                try? await Task.sleep(for: Self.previewFollowDelay)
                guard !Task.isCancelled else { return }
                previewSelection.select(id)
            }
        }
        .onChange(of: previewIsEditing) { _, editing in
            if editing { previewFollowTask?.cancel() }
        }
        .onChange(of: presentationID) { _, _ in
            isHovered = false
            previewFollowTask?.cancel()
        }
        .onDisappear {
            isHovered = false
            previewFollowTask?.cancel()
        }
        .onTapGesture { activate(entry) }
    }

    private var fill: Color {
        if isBatchSelected { return PanelSurface.batchSelectionFill(for: colorScheme) }
        if isSelected { return PanelSurface.selectionFill(for: colorScheme) }
        if isHovered { return PanelSurface.rowHoverFill(for: colorScheme) }
        return .clear
    }

    private var previewText: String {
        switch entry.kind {
        case .text: return entry.preview
        case .image: return text.imageEntryLabel
        case .files: return fileTitle(entry)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .text:
            if let color = entry.color {
                ColorSwatch(color: color, size: DS.Size.resultRowIcon - DS.Space.small)
            } else {
                Image(systemName: "doc.text")
                    .font(DS.Font.rowIcon)
                    .foregroundStyle(.secondary)
            }
        case .image:
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name),
                                        aspectRatio: entry.imageAspectRatio,
                                        contentMode: .fill)
                    .frame(width: DS.Size.resultRowIcon, height: DS.Size.resultRowIcon)
                    .clipShape(
                        RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(DS.Font.rowIcon)
                    .foregroundStyle(.secondary)
            }
        case .files:
            if entry.filePaths.count == 1,
               let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path) {
                ClipboardThumbnailImage(
                    source: .file(path: path),
                    aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path),
                    contentMode: .fill)
                    .frame(width: DS.Size.resultRowIcon, height: DS.Size.resultRowIcon)
                    .clipShape(
                        RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
            } else if let image = fileIcon(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: DS.Size.resultRowIcon - DS.Space.xSmall,
                           height: DS.Size.resultRowIcon - DS.Space.xSmall)
            } else {
                Image(systemName: "folder")
                    .font(DS.Font.rowIcon)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: DS.Space.xSmall) {
            if isHovered, entry.kind == .image, AppFeature.screenshot.isAvailable {
                Button { history.editImage(entry) } label: {
                    Image(systemName: "pencil")
                        .font(DS.Font.panelFloorEmphasis)
                        .frame(width: DS.Size.resultRowIcon - DS.Space.micro,
                               height: DS.Size.resultRowIcon - DS.Space.micro)
                        .background(
                            Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: DS.Radius.thumbnail,
                                                 style: .continuous))
                }
                .buttonStyle(.plain)
                .help(text.edit)
                .accessibilityLabel(text.edit)
            }
            if isHovered, entry.isPinned, let shortcutIndex {
                HStack(spacing: DS.Space.micro) {
                    ClipboardKeyCap(text: "⌘")
                    ClipboardKeyCap(text: "\(shortcutIndex + 1)")
                }
            }
            if isBatchSelected {
                Button {
                    history.toggleQuickBatchSelection(entry)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: DS.Size.resultRowIcon - DS.Space.xSmall,
                               height: DS.Size.resultRowIcon - DS.Space.xSmall)
                }
                .buttonStyle(.plain)
                .help(text.unselectMultiple)
                .accessibilityLabel(text.unselectMultiple)
            } else if isHovered {
                Button {
                    history.toggleQuickBatchSelection(entry)
                } label: {
                    Image(systemName: "circle")
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                        .frame(width: DS.Size.resultRowIcon - DS.Space.xSmall,
                               height: DS.Size.resultRowIcon - DS.Space.xSmall)
                }
                .buttonStyle(.plain)
                .help(text.selectMultiple)
                .accessibilityLabel(text.selectMultiple)
            }
        }
    }

    @ViewBuilder
    private func entryActions(_ entry: ClipboardHistoryEntry) -> some View {
        Button(l10n.s.menuPaste) {
            history.copyQuickEntry(entry)
        }
        Button(text.copy) {
            history.copyOnlyQuickEntry(entry)
        }
        Divider()
        Button(entry.isPinned ? text.unpin : text.pin) {
            history.togglePin(entry)
        }
        Button(text.moveUp) {
            history.move(entry, .up)
        }
        .disabled(!canReorderEntries || !history.canMove(entry, .up))
        Button(text.moveDown) {
            history.move(entry, .down)
        }
        .disabled(!canReorderEntries || !history.canMove(entry, .down))
        Divider()
        Button(text.delete, role: .destructive) {
            history.remove(entry)
        }
    }

    private func activate(_ entry: ClipboardHistoryEntry) {
        // Finder muscle memory: ⌘-click and ⇧-click build a selection.
        // A plain click pastes; on a selected row it pastes the selection.
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        if modifiers.contains(.command) {
            history.toggleQuickBatchSelection(entry)
        } else if modifiers.contains(.shift) {
            history.extendQuickBatchSelection(to: entry)
        } else if history.isQuickBatchSelected(entry) {
            history.copySelectedQuickEntry()
        } else {
            history.copyQuickEntry(entry)
        }
    }

    private func fileTitle(_ entry: ClipboardHistoryEntry) -> String {
        if entry.filePaths.count == 1 {
            return entry.fileNames.first ?? entry.preview
        }
        return String(format: text.fileCountFormat, entry.filePaths.count)
    }

    private func fileIcon(for entry: ClipboardHistoryEntry) -> NSImage? {
        guard entry.kind == .files,
              let path = entry.filePaths.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return nil }
        return ClipboardImageStore.fileIcon(atPath: path)
    }
}

private struct ClipboardHeaderBackButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(DS.Font.headerIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: DS.Size.headerIconSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

private struct ClipboardFilterButton: View {
    let filter: ClipboardQuickTypeFilter
    let isOpen: Bool
    /// The tooltip: the button names only the current filter.
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xSmall) {
                Image(systemName: filter.systemImage)
                    .font(DS.Font.menuIcon)
                    .frame(width: DS.Space.large)
                Text(filter.title)
                    .font(DS.Font.bar)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(DS.Font.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(.easeOut(duration: 0.2), value: isOpen)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.Space.small)
            .frame(height: DS.Size.barButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.barControl, style: .continuous)
                    .fill(hovered || isOpen
                          ? PanelSurface.selectionFill(for: colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title)
    }
}

private struct ClipboardMenuCircleButton: View {
    /// The button is two capsules with no text of its own.
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(.secondary)
            .frame(width: DS.Size.menuButton, height: DS.Size.menuButton)
            .background(
                Circle().fill(hovered
                              ? PanelSurface.rowHoverFill(for: colorScheme) : Color.clear)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(
            Circle().strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        )
        .onHover { hovered = $0 }
        .help(title)
        .accessibilityLabel(Text(title))
    }
}

private struct ClipboardBarButton<Label: View>: View {
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let label: Label
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, DS.Space.small)
                .frame(height: DS.Size.barButtonHeight)
                .contentShape(Capsule())
                .background(
                    Capsule().fill(hovered
                                   ? PanelSurface.selectionFill(for: colorScheme) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovered = $0 }
    }
}

private struct ClipboardKeyCap: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(DS.Font.keyCap)
            .foregroundStyle(.secondary)
            .offset(y: text == "↵" ? 1 : 0)
            .padding(.horizontal, DS.Space.xxSmall)
            .frame(minWidth: DS.Size.keyCap, minHeight: DS.Size.keyCap)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.keyCap, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1)
            )
    }
}

private struct ClipboardFilterPopover: View {
    @Binding var selection: ClipboardQuickTypeFilter
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.micro) {
            ForEach(ClipboardQuickTypeFilter.allCases) { filter in
                ClipboardMenuRow(
                    title: filter.title,
                    systemImage: filter.systemImage,
                    isSelected: filter == selection
                ) {
                    selection = filter
                    dismiss()
                }
            }
        }
    }
}

private struct ClipboardActionsPopover: View {
    let entry: ClipboardHistoryEntry
    let canReorder: Bool
    let dismiss: () -> Void
    let onEdit: () -> Void
    let onCopyText: () -> Void
    let onClearRecent: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var batchCount: Int { history.quickBatchCount }

    private var header: String {
        if batchCount > 0 {
            return String(format: text.pasteSelectedFormat, batchCount)
        }
        return entry.preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.micro) {
            Text(header)
                .font(DS.Font.panelFloor)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, DS.Space.small)
                .padding(.vertical, DS.Space.xSmall)
            ClipboardMenuDivider()
            ClipboardMenuRow(
                title: primaryTitle, systemImage: "doc.on.clipboard", shortcut: "↵"
            ) {
                history.copySelectedQuickEntry()
                dismiss()
            }
            ClipboardMenuRow(title: copyTitle, systemImage: "doc.on.doc") {
                history.copySelectedQuickEntryOnly()
                dismiss()
            }
            if batchCount == 0, entry.kind == .text {
                ClipboardMenuRow(title: text.edit, systemImage: "pencil") {
                    onEdit()
                }
            }
            if batchCount == 0, ClipboardImageTextCopy.imageURL(for: entry) != nil,
               AppFeature.screenOCR.isAvailable {
                ClipboardMenuRow(
                    title: FeatureStrings.screenshot(l10n.language).copyTextButton,
                    systemImage: "text.viewfinder"
                ) {
                    onCopyText()
                }
            }
            ClipboardMenuDivider()
            ClipboardMenuRow(
                title: entry.isPinned ? text.unpin : text.pin,
                systemImage: entry.isPinned ? "pin.slash" : "pin",
                shortcut: "⌥P"
            ) {
                history.togglePinSelectedQuickEntry()
                dismiss()
            }
            ClipboardMenuRow(
                title: text.moveUp, systemImage: "arrow.up",
                isEnabled: canReorder && history.canMove(entry, .up)
            ) {
                history.move(entry, .up)
                dismiss()
            }
            ClipboardMenuRow(
                title: text.moveDown, systemImage: "arrow.down",
                isEnabled: canReorder && history.canMove(entry, .down)
            ) {
                history.move(entry, .down)
                dismiss()
            }
            if batchCount > 0 {
                ClipboardMenuRow(title: text.clearSelection, systemImage: "xmark.circle") {
                    history.clearQuickBatchSelection()
                    dismiss()
                }
            }
            ClipboardMenuDivider()
            ClipboardMenuRow(
                title: deleteTitle,
                systemImage: "trash",
                shortcut: deleteShortcut,
                isDestructive: true
            ) {
                history.removeSelectedQuickEntries()
                dismiss()
            }
            ClipboardMenuRow(
                title: text.clearRecent, systemImage: "trash.slash", isDestructive: true,
                isEnabled: !history.recentEntries.isEmpty
            ) {
                onClearRecent()
            }
        }
    }

    private var primaryTitle: String {
        if batchCount > 0 {
            return String(format: text.pasteSelectedFormat, batchCount)
        }
        let target = history.pasteTargetDisplayName ?? "App"
        return "Paste to \(target)"
    }

    private var copyTitle: String {
        batchCount > 0 ? String(format: text.copySelectedFormat, batchCount) : text.copy
    }

    private var deleteTitle: String {
        batchCount > 0 ? String(format: text.deleteSelectedFormat, batchCount) : text.delete
    }

    /// Matches the key monitor: Option-Delete always deletes, and Command-Delete
    /// joins it only while a pile is selected.
    private var deleteShortcut: String {
        batchCount > 0 ? "⌘⌫" : "⌥⌫"
    }
}

private struct ClipboardAppMenuPopover: View {
    let onTogglePreview: () -> Void
    let onClearRecent: () -> Void
    let onClose: () -> Void
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    var body: some View {
        VStack(spacing: DS.Space.micro) {
            ClipboardMenuRow(
                title: history.quickPreviewPresented ? text.hidePreview : text.showPreview,
                systemImage: "sidebar.right", shortcut: "Space"
            ) {
                onTogglePreview()
            }
            ClipboardMenuDivider()
            ClipboardMenuRow(
                title: text.clearRecent + "…", systemImage: "trash", isDestructive: true,
                isEnabled: !history.recentEntries.isEmpty
            ) {
                onClearRecent()
            }
            ClipboardMenuRow(title: l10n.s.menuClose, systemImage: "xmark", shortcut: "esc") {
                onClose()
            }
        }
    }
}

private struct ClipboardMenuRow: View {
    let title: String
    var systemImage: String?
    var shortcut: String?
    var isSelected = false
    var isDestructive = false
    var isEnabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.small) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(DS.Font.menuIcon)
                        .frame(width: DS.Space.large)
                }
                Text(title)
                    .font(DS.Font.menuRow)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.small)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DS.Font.panelFloorEmphasis)
                } else if let shortcut {
                    Text(shortcut)
                        .font(DS.Font.keyCap)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isDestructive ? Color.red : .primary)
            .padding(.horizontal, DS.Space.small)
            .frame(height: DS.Size.menuRowHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.menuRow, style: .continuous)
                    .fill(hovered && isEnabled
                          ? PanelSurface.selectionFill(for: colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovered = $0 }
    }
}

private struct ClipboardMenuDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(PanelSurface.border(for: colorScheme))
            .frame(height: 1)
            .padding(.vertical, DS.Space.micro)
    }
}

private struct ClipboardMenuSurface: ViewModifier {
    let width: CGFloat?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.menuPanel, style: .continuous)
        content
            .padding(DS.Space.small)
            .frame(width: width)
            .background(shape.fill(.regularMaterial))
            .overlay(shape.strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

extension View {
    fileprivate func clipboardMenuSurface(width: CGFloat?) -> some View {
        modifier(ClipboardMenuSurface(width: width))
    }
}

/// Turns off the rubber-band bounce of the enclosing scroll view. SwiftUI's
/// `scrollBounceBehavior` still bounces once the content is larger than the
/// view, and the list has nothing to show past its ends.
private struct ScrollBounceDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> BounceDisablingView { BounceDisablingView() }
    func updateNSView(_ view: BounceDisablingView, context: Context) { view.apply() }

    final class BounceDisablingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            // The scroll view is an ancestor only once SwiftUI has placed
            // this view, which is after the current layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else { return }
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
            }
        }
    }
}
