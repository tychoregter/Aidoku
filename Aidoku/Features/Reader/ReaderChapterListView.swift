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
        chapterSet: ((AidokuRunner.Chapter) -> Void)? = nil
    ) {
        self.source = source
        self.manga = manga
        self.chapterList = chapterList
        self._chapter = State(initialValue: chapter)
        self._pageCounts = State(initialValue: pageCounts)
        self.chapterSet = chapterSet
    }

    var body: some View {
        PlatformNavigationStack {
            ScrollViewReader { proxy in
                List(orderedChapterList) { chapter in
                    Button {
                        self.chapter = chapter
                        chapterSet?(chapter)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(chapter.sourceDisplayTitle)
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                                if showPageCounts.value {
                                    Text(
                                        String(
                                            format: NSLocalizedString("%i_PAGES"),
                                            pageCounts[chapter.key] ?? 0
                                        )
                                    )
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
                }
                .onAppear {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(chapter.id, anchor: .center)
                    }
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
        let order = ChapterListOrder(
            rawValue: AppSettings.library.chapterListOrder.get()
        ) ?? .automatic
        return order.orderedChapters(chapterList, for: manga)
    }

    private func loadPageCount(for chapter: AidokuRunner.Chapter) async {
        guard showPageCounts.value, pageCounts[chapter.key] == nil, let source else { return }
        guard let pages = try? await source.getPageList(manga: manga, chapter: chapter) else { return }
        guard !Task.isCancelled else { return }
        pageCounts[chapter.key] = pages.count
    }
}
