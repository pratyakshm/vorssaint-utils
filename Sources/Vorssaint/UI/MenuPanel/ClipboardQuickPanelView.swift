// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @FocusState private var searchFocused: Bool
    @State private var previewSelection = QuickPreviewSelection()
    @State private var previewIsEditing = false
    @State private var clearingIDs: [UUID: Date]?

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

    private var layout: ClipboardHistoryLayout {
        .list
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // Two proportional columns while the preview is open: the list
            // takes a third, the sidebar takes the rest. A fixed sidebar
            // width starved the preview on wide windows.
            GeometryReader { geo in
                HStack(spacing: 0) {
                    content
                        .frame(width: history.quickPreviewPresented ? geo.size.width * 0.35 : nil)
                    if history.quickPreviewPresented {
                        Divider()
                        QuickPreviewPane(text: text,
                                         selection: previewSelection,
                                         isEditing: $previewIsEditing,
                                         onClose: { history.setQuickPreviewPresented(false) })
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            previewSelection.select(history.selectedQuickEntryID)
            DispatchQueue.main.async { searchFocused = true }
        }
        .onDisappear {
            previewSelection.select(nil)
            previewIsEditing = false
        }
        .onChange(of: history.quickSelectionID) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickQuery) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
        .onChange(of: history.quickWindowPresentationID) { _, _ in
            previewSelection.select(history.selectedQuickEntryID)
        }
    }

    private var toolbar: some View {
        HStack(spacing: DS.Space.rowTitleGap) {
            TextField(text.search, text: $history.quickQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($searchFocused)
                .frame(height: 44)
            Button {
                history.toggleQuickPreview()
            } label: {
                Label(text.previewLabel,
                      systemImage: history.quickPreviewPresented ? "sidebar.right" : "eye")
                    .foregroundStyle(history.quickPreviewPresented ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(history.selectedQuickEntry == nil && !history.quickPreviewPresented)
            .help(text.previewLabel)
            .accessibilityLabel(text.previewLabel)
            Button {
                history.hideHistoryWindow()
            } label: {
                Image(systemName: "xmark")
                    .font(DS.Font.panelFloorEmphasis)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuClose)
            .accessibilityLabel(l10n.s.menuClose)
        }
        .padding(.horizontal, DS.Space.medium)
        .padding(.vertical, DS.Space.medium)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState(history.entries.isEmpty ? text.empty : text.noResults)
        } else {
            ScrollViewReader { proxy in
                // A plain stack for an ordinary history: with every entry
                // already laid out, scrolling is the clip view moving and
                // nothing else, which is what makes it smooth. Only a very
                // large history goes lazy, where building every entry (and
                // decoding every thumbnail) on open would cost more than the
                // placement work a lazy stack does per tick.
                Group {
                    ScrollView {
                        Group {
                            if filtered.count <= Self.eagerRowLimit {
                                VStack(alignment: .leading, spacing: 0) { topAnchor; sections }
                            } else {
                                LazyVStack(alignment: .leading, spacing: 0) { topAnchor; sections }
                            }
                        }
                        .padding(.horizontal, DS.Space.medium)
                        .padding(.bottom, Self.listVerticalInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(ScrollBounceDisabler())
                .onChange(of: history.quickSelectionID) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickSelectionIsVisible) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickQuery) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                // The window is only hidden between uses, so without this it
                // reopens wherever it was scrolled, while the selection and
                // ⌘1 to ⌘9 already start from the first entries.
                .onChange(of: history.quickWindowPresentationID) { _, _ in
                    proxy.scrollTo(Self.topAnchorID, anchor: .top)
                }
            }
        }
    }

    /// Emits the headers, rows and cards straight into the enclosing lazy
    /// stack. If wrapped, the whole section becomes one lazy unit and builds
    /// every entry.
    private static let eagerRowLimit = 300

    private static let listVerticalInset: CGFloat = DS.Space.xSmall

    /// The list's top inset, above the first section's header that
    /// scrolling to the first row would leave cut off. Scrolling it into
    /// place lands exactly where a first open starts.
    private static let topAnchorID = "clipboard-list-top"

    private var topAnchor: some View {
        Color.clear
            .frame(height: Self.listVerticalInset)
            .id(Self.topAnchorID)
    }

    /// Recents bucketed outside the result builder: a `let` plus a `for`
    /// loop inside a `@ViewBuilder` does not compile.
    private var bucketedRecents: [(offset: Int, bucket: ClipboardHistoryDateBucket,
                                   entries: [ClipboardHistoryEntry])] {
        ClipboardHistoryDateBucket.bucketed(history.recentEntries).enumerated().map {
            (offset: $0.offset, bucket: $0.element.bucket, entries: $0.element.entries)
        }
    }

    /// Tinycast-style sections: Pinned, then Today / Yesterday / This Week /
    /// This Month / Earlier. A search lists its matches by relevance with no
    /// headers. No row dividers: selection is a rounded-rect fill.
    @ViewBuilder
    private var sections: some View {
        if history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows(title: text.pinned, entries: history.pinnedEntries, isFirst: true)
            ForEach(bucketedRecents, id: \.offset) { group in
                rows(title: group.bucket.title, entries: group.entries,
                     isFirst: history.pinnedEntries.isEmpty && group.offset == 0)
            }
        } else {
            rows(title: nil, entries: filtered, isFirst: true)
        }
    }

    @ViewBuilder
    private func rows(title: String?, entries: [ClipboardHistoryEntry],
                      followsSection: Bool = false, isFirst: Bool = false) -> some View {
        if !entries.isEmpty {
            if followsSection {
                Divider()
                    .padding(.horizontal, DS.Space.xSmall)
                    .padding(.vertical, DS.Space.xSmall)
            }
            if let title {
                Text(title)
                    .font(DS.Font.panelTitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, DS.Space.rowTitleGap)
                    .padding(.top, isFirst ? DS.Space.xxSmall : DS.Space.medium)
                    .padding(.bottom, DS.Space.xxSmall)
            }
            ForEach(entries, id: \.id) { entry in
                entryView(entry)
            }
        }
    }

    private func entryView(_ entry: ClipboardHistoryEntry) -> some View {
        QuickEntryView(layout: layout,
                       entry: entry,
                       tokens: searchTokens,
                       shortcutIndex: shortcutIndex(for: entry),
                       isSelected: history.quickSelectionIsVisible
                          && history.selectedQuickEntryID == entry.id,
                       isBatchSelected: history.isQuickBatchSelected(entry),
                       canReorderEntries: canReorderEntries,
                       previewIsEditing: previewIsEditing,
                       presentationID: history.quickWindowPresentationID,
                       language: l10n.language,
                       previewSelection: previewSelection)
            .equatable()
            .id(entry.id)
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
        HStack(spacing: DS.Space.rowTitleGap) {
            if history.quickBatchCount > 0 {
                Button(String(format: text.pasteSelectedFormat, history.quickBatchCount)) {
                    history.copySelectedQuickEntry()
                }
                .buttonStyle(.borderedProminent)
                Button(String(format: text.copySelectedFormat, history.quickBatchCount)) {
                    history.copySelectedQuickEntryOnly()
                }
                Button(String(format: text.deleteSelectedFormat, history.quickBatchCount), role: .destructive) {
                    history.removeSelectedQuickEntries()
                }
                Button(text.clearSelection) {
                    history.clearQuickBatchSelection()
                }
            } else {
                Button {
                    clearingIDs = history.recentEntriesSnapshot
                } label: {
                    Label(text.clearRecent, systemImage: "trash")
                }
                .disabled(history.recentEntries.isEmpty)
                .modifier(ClipboardClearRecentConfirmation(entryIDs: $clearingIDs))
            }
            Spacer()
            // Tinycast-style primary action: paste names the app it lands in.
            if history.quickBatchCount == 0, history.selectedQuickEntry != nil {
                Button("Paste to \(Self.pasteTargetName) ↵") {
                    history.copySelectedQuickEntry()
                }
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: DS.Space.xSmall) {
                Image(systemName: "doc.on.clipboard")
                Text("\(history.entries.count)")
            }
            .font(DS.Font.panelFloor)
            .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, DS.Space.medium)
        .padding(.vertical, DS.Space.small)
    }

    private func shortcutIndex(for entry: ClipboardHistoryEntry) -> Int? {
        filtered.prefix(9).firstIndex(where: { $0.id == entry.id })
    }

    /// The app a paste lands in, for the Tinycast-style "Paste to {app}" footer.
    private static var pasteTargetName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "App"
    }

    private func scrollSelectedEntry(with proxy: ScrollViewProxy) {
        guard history.quickSelectionIsVisible, let id = history.selectedQuickEntryID else { return }
        // No anchor and no animation: the list moves only when the selected
        // row is off screen, and then straight to it, so every arrow press
        // costs the same and the rows never redraw mid-slide.
        proxy.scrollTo(id)
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
    @Binding var isEditing: Bool
    let onClose: () -> Void
    @ObservedObject private var history = ClipboardHistoryService.shared

    var body: some View {
        ClipboardEntryPreviewSidebar(text: text,
                                     entry: ClipboardHistorySelection.previewEntry(
                                        preferredID: selection.entryID,
                                        visibleEntries: history.filteredQuickEntries,
                                        selectedEntry: history.selectedQuickEntry),
                                     isEditing: $isEditing,
                                     onClose: onClose)
    }
}

/// One entry, as a row of the list. Keep hover within
/// it so moving the pointer does not rebuild the others. Value inputs let
/// SwiftUI skip entries unaffected by selection or history changes.
private struct QuickEntryView: View, Equatable {
    let layout: ClipboardHistoryLayout
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
    @State private var isHovered = false
    /// The pane follows a row only once the pointer has rested on it: while
    /// rows stream under a still pointer during a scroll, every one of them
    /// would otherwise redraw the pane, and a long entry costs a frame or two
    /// each time.
    @State private var previewFollowTask: Task<Void, Never>?
    private static let previewFollowDelay: Duration = .milliseconds(120)
    /// Fixed 3:2 thumbnail slot, the text row's 26pt content height, so an
    /// image row never grows taller than a text row.
    private static let thumbnailSlot = CGSize(width: 39, height: 26)

    private var history: ClipboardHistoryService { .shared }
    private var l10n: L10n { .shared }
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(language) }

    // Preview selection is a channel to the sidebar, not part of this row's
    // appearance, so it stays out of the comparison.
    static func == (lhs: QuickEntryView, rhs: QuickEntryView) -> Bool {
        lhs.layout == rhs.layout
            && lhs.entry == rhs.entry
            && lhs.tokens == rhs.tokens
            && lhs.shortcutIndex == rhs.shortcutIndex
            && lhs.isSelected == rhs.isSelected
            && lhs.isBatchSelected == rhs.isBatchSelected
            && lhs.canReorderEntries == rhs.canReorderEntries
            && lhs.previewIsEditing == rhs.previewIsEditing
            && lhs.presentationID == rhs.presentationID
            && lhs.language == rhs.language
    }

    var body: some View {
        row
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

    private var row: some View {
        HStack(alignment: .center, spacing: DS.Space.medium) {
            selectionButton
            entryContent(entry)
            Spacer(minLength: 0)
            entryTrailing(entry, isHovered: isHovered)
        }
        .padding(.horizontal, DS.Space.rowTitleGap)
        .padding(.vertical, DS.Space.xSmall)
        .frame(minHeight: 38)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(rowBackground(isSelected: isSelected,
                                    isBatchSelected: isBatchSelected,
                                    isHovered: isHovered))
        )
    }

    private var selectionButton: some View {
        Button {
            history.toggleQuickBatchSelection(entry)
        } label: {
            leadingMarker(entry: entry,
                          isBatchSelected: isBatchSelected,
                          isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .help(isBatchSelected ? text.unselectMultiple : text.selectMultiple)
    }

    @ViewBuilder
    private func entryContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            HStack(alignment: .center, spacing: DS.Space.rowTitleGap) {
                if let color = entry.color {
                    ColorSwatch(color: color, size: 14)
                }
                SearchHighlightText.text(entry.preview, tokens: tokens, fontSize: 12)
                    .font(DS.Font.panelBody)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            HStack(alignment: .center, spacing: DS.Space.rowTitleGap) {
                if let name = entry.imageFile {
                    ClipboardThumbnailImage(source: .stored(name: name),
                                            aspectRatio: entry.imageAspectRatio,
                                            contentMode: .fill)
                        .frame(width: Self.thumbnailSlot.width, height: Self.thumbnailSlot.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                SearchHighlightText.text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)",
                                         tokens: tokens, fontSize: 12)
                    .font(DS.Font.panelBody)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
        case .files:
            if entry.filePaths.count == 1,
               let path = entry.filePaths.first,
               ClipboardImageStore.isImageFile(atPath: path) {
                HStack(alignment: .center, spacing: DS.Space.rowTitleGap) {
                    ClipboardThumbnailImage(source: .file(path: path),
                                            aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path),
                                            contentMode: .fill)
                        .frame(width: Self.thumbnailSlot.width, height: Self.thumbnailSlot.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        SearchHighlightText.text(entry.fileNames.first ?? entry.preview, tokens: tokens, fontSize: 12)
                            .font(DS.Font.panelBody)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let dim = ClipboardImageStore.imageDimensionsLabel(atPath: path) {
                            Text("\(text.imageEntryLabel) · \(dim)")
                                .font(DS.Font.panelBody)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(path)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    // A count of several files is no text the search reads.
                    SearchHighlightText.text(fileTitle(entry),
                                             tokens: entry.filePaths.count == 1 ? tokens : [],
                                             fontSize: 12)
                        .font(DS.Font.panelBody)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.filePaths.count > 1 {
                        SearchHighlightText.text(entry.preview, tokens: tokens, fontSize: 11)
                            .font(DS.Font.panelFloor)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.filePaths.joined(separator: "\n"))
            }
        }
    }

    @ViewBuilder
    private func entryTrailing(_ entry: ClipboardHistoryEntry, isHovered: Bool) -> some View {
        if isHovered {
            HStack(spacing: DS.Space.rowTextStack) {
                if entry.kind == .image, AppFeature.screenshot.isAvailable {
                    Button { history.editImage(entry) } label: {
                        Image(systemName: "pencil")
                            .font(DS.Font.panelFloorEmphasis)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(text.edit)
                    .accessibilityLabel(text.edit)
                }
                Button {
                    history.copyOnlyQuickEntry(entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(DS.Font.panelFloorEmphasis)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(text.copy)
                Menu {
                    entryActions(entry)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(DS.Font.panelFloorEmphasis)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } else {
            // Tinycast parity: no timestamp. Pinned rows show their ⌘-digit
            // slot; everything else keeps the trailing edge clean.
            if entry.isPinned, let shortcutIndex {
                HStack(spacing: 2) {
                    Text("⌘")
                        .font(DS.Font.panelBody)
                        .padding(.horizontal, DS.Space.xxSmall)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                    Text("\(shortcutIndex + 1)")
                        .font(DS.Font.panelBody)
                        .padding(.horizontal, DS.Space.xxSmall)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                }
                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func leadingMarker(entry: ClipboardHistoryEntry,
                               isBatchSelected: Bool,
                               isHovered: Bool) -> some View {
        if isBatchSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 25, height: 25)
        } else if isHovered {
            Image(systemName: "circle")
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .frame(width: 25, height: 25)
        } else if entry.kind == .image {
            Color.clear
                .frame(width: 25, height: 25)
        } else if entry.kind == .files,
                  entry.filePaths.count == 1,
                  let path = entry.filePaths.first,
                  ClipboardImageStore.isImageFile(atPath: path) {
            Color.clear
                .frame(width: 25, height: 25)
        } else if entry.kind == .text {
            Color.clear
                .frame(width: 25, height: 25)
        } else if let icon = fileIcon(for: entry) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .frame(width: 25, height: 25)
        } else {
            Image(systemName: entry.isPinned ? "pin.fill" : "folder")
                .font(DS.Font.panelFloorEmphasis)
                .foregroundStyle(entry.isPinned ? Color.accentColor : Color.secondary)
                .frame(width: 25, height: 25)
        }
    }

    private func fileIcon(for entry: ClipboardHistoryEntry) -> NSImage? {
        guard entry.kind == .files,
              let path = entry.filePaths.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return nil }
        return ClipboardImageStore.fileIcon(atPath: path)
    }

    private func rowBackground(isSelected: Bool,
                               isBatchSelected: Bool,
                               isHovered: Bool) -> Color {
        if isBatchSelected { return Color.accentColor.opacity(isHovered ? 0.17 : 0.13) }
        if isSelected { return Color.white.opacity(isHovered ? 0.13 : 0.10) }
        if isHovered { return Color.primary.opacity(0.055) }
        return .clear
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
