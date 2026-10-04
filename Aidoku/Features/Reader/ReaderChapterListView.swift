//
//  ReaderChapterListView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/22.
//

import SwiftUI
import AidokuRunner

struct ReaderChapterListView: View {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    var chapterList: [AidokuRunner.Chapter]
    @State var chapter: AidokuRunner.Chapter
    @State private var pageCounts: [String: Int]
    @State private var progressPages: [String: Int]
    @State private var readingHistory: [String: (page: Int, date: Int)] = [:]
    @State private var listPreferences: ChapterListPreferences
    private let liveCurrentPage: Int?
    @StateObject private var showPageCounts = UserDefaultsBool(key: AppSettings.library.showChapterPageCounts.key)
    @StateObject private var chapterListOrderObserver = UserDefaultsObserver(
        key: AppSettings.library.chapterListOrder.key
    )
    var chapterSet: ((AidokuRunner.Chapter) -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        chapterList: [AidokuRunner.Chapter],
        chapter: AidokuRunner.Chapter,
        pageCounts: [String: Int] = [:],
        currentPage: Int? = nil,
        listPreferences: ChapterListPreferences,
        chapterSet: ((AidokuRunner.Chapter) -> Void)? = nil
    ) {
        self.source = source
        self.manga = manga
        self.chapterList = chapterList
        self._chapter = State(initialValue: chapter)
        self._pageCounts = State(initialValue: pageCounts)
        self._progressPages = State(initialValue: currentPage.map { $0 > 0 ? [chapter.key: $0] : [:] } ?? [:])
        self._listPreferences = State(initialValue: listPreferences)
        self.liveCurrentPage = currentPage
        self.chapterSet = chapterSet
    }

    var body: some View {
        let visibleChapters = orderedChapterList
        let isNumberedOrder = BookGapPresentation.isNumberedOrder(visibleChapters)
        PlatformNavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(visibleChapters.enumerated()), id: \.element.id) { entry in
                        let index = entry.offset
                        let chapter = entry.element
                        let missingBefore = isNumberedOrder && index > 0
                            ? BookGapPresentation.missingCount(between: visibleChapters[index - 1], and: chapter)
                            : 0
                        let missingAfter = isNumberedOrder && index + 1 < visibleChapters.count
                            ? BookGapPresentation.missingCount(between: chapter, and: visibleChapters[index + 1])
                            : 0
                        if missingBefore > 0 {
                            MissingBooksWarningRow(count: missingBefore)
                        }
                        Button {
                            self.chapter = chapter
                            chapterSet?(chapter)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(chapter.sourceDisplayTitle)
                                        .foregroundColor(.primary)
                                        .font(.subheadline)
                                    if showPageCounts.value, supportsPageCounts {
                                        Text(chapterPageCountSubtitle(
                                            pageCount: pageCounts[chapter.key] ?? 0,
                                            progressPage: progressPages[chapter.key]
                                        ))
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                            // Reserve the subtitle's final height while its
                                            // page count loads so the list cannot shift.
                                            .opacity(pageCounts[chapter.key] == nil ? 0 : 1)
                                            .accessibilityHidden(pageCounts[chapter.key] == nil)
                                    } else if let subtitle = chapter.formattedSubtitle(
                                        page: nil,
                                        sourceKey: manga.sourceKey
                                    ) {
                                        Text(subtitle)
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                    }
                                }
                                Spacer()
                                if chapter == self.chapter {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .id(chapter.id)
                        .task(id: "\(chapter.id)-\(showPageCounts.value)") {
                            await loadPageCount(for: chapter)
                        }
                        .listRowSeparator(missingAfter > 0 ? .hidden : .visible, edges: .bottom)
                    }
                }
                .onAppear {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(chapter.id, anchor: .center)
                    }
                }
                .task(id: "\(manga.identifier)-\(showPageCounts.value)") {
                    await loadReadingProgressIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: .filteredChapters)) { notification in
                    guard let id = notification.object as? MangaIdentifier, id == manga.identifier else { return }
                    listPreferences = ChapterListPreferences.load(for: manga.identifier)
                    Task { await loadReadingProgressIfNeeded() }
                }
            }
            .navigationTitle(NSLocalizedString("CHAPTERS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
    }

    private var orderedChapterList: [AidokuRunner.Chapter] {
        // Read the observer so this list updates immediately when the setting changes.
        _ = chapterListOrderObserver.observedValues[AppSettings.library.chapterListOrder.key]
        let ordered = ChapterListPresentation.orderedChapters(
            chapterList,
            for: manga,
            option: ChapterSortOption(flags: listPreferences.flags),
            ascending: listPreferences.flags & ChapterFlagMask.sortAscending != 0
        )
        return ChapterListPresentation.filteredChapters(
            ordered,
            for: manga,
            filters: ChapterFilterOption.parseOptions(flags: listPreferences.flags),
            language: listPreferences.language,
            scanlators: listPreferences.scanlators,
            readingHistory: readingHistory
        )
    }

    private var supportsPageCounts: Bool {
        ["komga", "kavita", "suwayomi"].contains { manga.sourceKey.hasPrefix($0) }
    }

    private func loadPageCount(for chapter: AidokuRunner.Chapter) async {
        guard showPageCounts.value, supportsPageCounts, pageCounts[chapter.key] == nil, let source else { return }
        guard let pages = try? await source.getPageList(manga: manga, chapter: chapter) else { return }
        guard !Task.isCancelled else { return }
        pageCounts[chapter.key] = pages.count
    }

    private func loadReadingProgressIfNeeded() async {
        let history = await CoreDataManager.shared.getReadingHistory(mangaId: manga.identifier)
        guard !Task.isCancelled else { return }

        readingHistory = history
        guard showPageCounts.value, supportsPageCounts else { return }
        progressPages = history.compactMapValues { $0.page > 0 ? $0.page : nil }
        // The reader's live position may be newer than the most recent persisted update.
        if let liveCurrentPage, liveCurrentPage > 0 {
            progressPages[chapter.key] = liveCurrentPage
        }
    }
}
