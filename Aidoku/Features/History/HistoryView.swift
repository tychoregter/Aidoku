//
//  HistoryView.swift
//  Aidoku
//
//  Created by Skitty on 7/30/25.
//

import AidokuRunner
import LocalAuthentication
import SwiftUI
import SwiftUIIntrospect

struct HistoryView: View {
    @StateObject private var viewModel = ViewModel()

    @State private var searchText = ""
    @State private var entryToDelete: HistoryEntry?
    @State private var showClearHistoryConfirm = false
    @State private var showDeleteConfirm = false

    @State private var triggerLoadMoreVisibleCheck = false
    @State private var loadTask: Task<(), Never>?

    @State private var locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")

    @State private var listSelection: String? // fix for list highlighting being buggy

    @State private var openingLastRead = false

    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        Group {
            if locked {
                lockedView
            } else if viewModel.filteredHistory.isEmpty && viewModel.loadingState == .complete {
                UnavailableView(
                    NSLocalizedString("NO_HISTORY"),
                    systemImage: "book.fill",
                    description: Text(NSLocalizedString("NO_HISTORY_TEXT"))
                )
                .ignoresSafeArea()
            } else {
                List(selection: $listSelection) {
                    let rows = viewModel.filteredHistory.values
                        .sorted { $0.daysAgo < $1.daysAgo }
                        .flatMap(\.entries)
                    let lastEntryId = rows.last?.chapterId
                    ForEach(rows, id: \.chapterId) { row in
                        cellView(entry: row, isLast: row.chapterId == lastEntryId)
                    }
                    loadMoreView
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 1)
                .environment(\.defaultMinListHeaderHeight, 1) // for ios 15
                .scrollBackgroundHiddenPlease()
                .scrollDismissesKeyboardImmediately()
                .background(Color(uiColor: .systemBackground))
            }
        }
        .customSearchable(
            text: $searchText,
            stacked: false,
            onSubmit: {
                Task {
                    await viewModel.search(query: searchText, delay: false)
                }
            },
            onCancel: {
                Task {
                    await viewModel.search(query: searchText, delay: false)
                }
            }
        )
        .environment(\.autocorrectionDisabled, true)
        .onChange(of: searchText) { newValue in
            Task {
                await viewModel.search(query: newValue, delay: true)
            }
        }
        .animation(.default, value: viewModel.filteredHistory)
        .navigationTitle(NSLocalizedString("HISTORY"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if UserDefaults.standard.bool(forKey: "History.lockHistoryTab") {
                    Button {
                        if locked {
                            Task {
                                await unlock()
                            }
                        } else {
                            locked = true
                        }
                    } label: {
                        Image(systemName: locked ? "lock" : "lock.open")
                    }
                }
                Button {
                    showClearHistoryConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialogOrAlert(NSLocalizedString("CLEAR_READ_HISTORY"), isPresented: $showClearHistoryConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("CLEAR"), role: .destructive) {
                viewModel.clearHistory()
            }
        } message: {
            Text(NSLocalizedString("CLEAR_READ_HISTORY_TEXT"))
        }
        .confirmationDialogOrAlert(NSLocalizedString("CLEAR_READ_HISTORY"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                if let entryToDelete {
                    Task {
                        await viewModel.removeHistory(entry: entryToDelete)
                    }
                }
            }
            Button(NSLocalizedString("REMOVE_ALL_MANGA_HISTORY"), role: .destructive) {
                if let entryToDelete {
                    Task {
                        await viewModel.removeHistory(entry: entryToDelete, all: true)
                    }
                }
            }
        } message: {
            Text(NSLocalizedString("CLEAR_READ_HISTORY_TEXT"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyLockTabSetting)) { _ in
            // update locked state when the setting changes
            locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // lock the view when the app is backgrounded
            locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyTabReselected)) { _ in
            // the history tab was selected while already at the top of the list
            Task {
                await continueReading()
            }
        }
    }

    var lockedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(NSLocalizedString("HISTORY_LOCKED"))
                .fontWeight(.medium)

            Button(NSLocalizedString("VIEW_HISTORY")) {
                Task {
                    await unlock()
                }
            }
        }
        .padding(.top, -52) // slight offset to account for search bar and make the view more centered
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func cellView(entry: HistoryEntry, isLast: Bool) -> some View {
        let source = viewModel.sourceCache[entry.chapterId.sourceKey]
        let manga = viewModel.mangaCache[entry.chapterId.mangaIdentifier]
        return HistoryEntryCell(
            entry: entry,
            source: source,
            manga: manga,
            chapter: viewModel.chapterCache[entry.chapterId]
        ) {
            if let manga {
                path.push(MangaViewController(manga: manga, parent: path.rootViewController))
            }
        }
        .equatable()
        .contentShape(Rectangle())
        .listRowSeparator(.hidden, edges: .top)
        .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
        .introspect(.listCell, on: .iOS(.v16, .v17, .v18, .v26, .v27)) { entity in
            // match cell background color to list background color when not selected (plain cell style)
            guard let cell = entity as? UICollectionViewListCell, cell.tag != 1 else { return }
            cell.backgroundConfiguration = UIBackgroundConfiguration.listPlainCell()
            cell.tag = 1
        }
        .swipeActions(edge: .trailing) {
            Button {
                entryToDelete = entry
                showDeleteConfirm = true
            } label: {
                Label(NSLocalizedString("DELETE"), systemImage: "trash")
            }
            .tint(.red) // adding destructive role breaks animation, so do this instead
        }
        .id(entry.chapterId)
        .tag(entry.chapterId)
        .offsetListSeparator()
    }

    @ViewBuilder
    var loadMoreView: some View {
        VStack {
            if viewModel.loadingState != .complete {
                ProgressView()
                    .progressViewStyle(.circular)
                    .onReportScrollVisibilityChange(trigger: $triggerLoadMoreVisibleCheck) { visible in
                        Task {
                            await loadTask?.value
                            if visible {
                                tryLoadingMore()
                            }
                        }
                    }
                    .onChange(of: viewModel.filteredHistory) { _ in
                        // trigger check to see if the loading more view is still visible after content is added
                        Task {
                            try? await Task.sleep(nanoseconds: 10_000_000) // wait 10ms
                            triggerLoadMoreVisibleCheck = true
                        }
                    }
                    .onAppear {
                        tryLoadingMore()
                    }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(.zero)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // load more history entries if the loading state is idle
    func tryLoadingMore() {
        Task {
            if viewModel.loadingState == .idle {
                await viewModel.loadMore()
            }
        }
    }

    // open the most recently read manga, resuming from the chapter it left off on
    func continueReading() async {
        guard !locked, !openingLastRead else { return }
        openingLastRead = true
        defer { openingLastRead = false }

        let mangaId = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getRecentHistory(limit: 1, offset: 0, context: context)
                .first
                .map { $0.identifier.mangaIdentifier }
        }
        guard let mangaId else { return }

        var manga = viewModel.mangaCache[mangaId]
        if manga == nil {
            manga = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getManga(
                    mangaId: mangaId,
                    context: context
                )?.toNewManga()
            }
        }

        let (chapters, nextChapter) = await MangaManager.shared.getNextChapter(
            mangaId: mangaId,
            fallbackChapters: manga?.chapters,
            fetchIfNeeded: true
        )

        var targetManga = manga ?? AidokuRunner.Manga(sourceKey: mangaId.sourceKey, key: mangaId.mangaKey, title: "")
        if !chapters.isEmpty {
            targetManga.chapters = chapters
        }

        // the user can navigate elsewhere while the chapters are loading
        guard
            let rootViewController = path.rootViewController,
            rootViewController.view.window != nil,
            rootViewController.navigationController?.topViewController === rootViewController
        else { return }

        guard
            let chapter = nextChapter,
            let source = SourceManager.shared.store.source(for: mangaId.sourceKey)
        else {
            // nothing left to read (or the source is missing), so open the manga page instead.
            // without a source to load details from or anything stored to show, the page would be blank
            guard
                SourceManager.shared.store.isInstalled(sourceKey: mangaId.sourceKey) || !targetManga.title.isEmpty
            else {
                return
            }
            path.push(MangaViewController(manga: targetManga, parent: rootViewController))
            return
        }

        let readerController = ReaderViewController(
            source: source,
            manga: targetManga,
            chapter: chapter
        )
        let navigationController = ReaderNavigationController(readerViewController: readerController)
        navigationController.modalPresentationStyle = .fullScreen
        path.present(navigationController)
    }

    // prompt for biometrics to unlock the view
    func unlock() async {
        let context = LAContext()
        let success: Bool

        do {
            success = try await context.evaluatePolicy(
                .defaultPolicy,
                localizedReason: NSLocalizedString("AUTH_FOR_HISTORY")
            )
        } catch {
            // The error is to be displayed to users, so we can ignore it.
            return
        }

        guard success else {
            return
        }

        locked = false
    }
}

private struct HistoryEntryCell: View, @MainActor Equatable {
    let entry: HistoryEntry

    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga?
    let chapter: AidokuRunner.Chapter?

    var onPressed: (() -> Void)?

    private static let coverImageWidth: CGFloat = 56

    var body: some View {
        Button {
            onPressed?()
        } label: {
            HStack(spacing: 12) {
                MangaCoverView(
                    source: source,
                    coverImage: manga?.cover ?? "",
                    paletteIdentifier: manga?.identifier,
                    width: Self.coverImageWidth,
                    height: Self.coverImageWidth * 3/2,
                    downsampleWidth: Self.coverImageWidth,
                    isNSFW: manga?.contentRating == .nsfw
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(manga?.title ?? "")
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let chapterName {
                        Text(chapterName)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    Text(timeText)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }

    private var chapterName: String? {
        guard let chapter else { return nil }
        if let title = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return chapter.sourceDisplayTitle
    }

    private var timeText: String {
        let calendar = Calendar.autoupdatingCurrent
        let dayDifference = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: entry.date),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        guard dayDifference > 0 else {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: entry.date)
        }
        if dayDifference == 1 {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            return formatter.localizedString(from: DateComponents(day: -1))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        return formatter.localizedString(for: entry.date, relativeTo: Date())
    }

    static func == (lhs: HistoryEntryCell, rhs: HistoryEntryCell) -> Bool {
        lhs.entry == rhs.entry
            && lhs.manga == rhs.manga
            && lhs.chapter == rhs.chapter
    }
}
