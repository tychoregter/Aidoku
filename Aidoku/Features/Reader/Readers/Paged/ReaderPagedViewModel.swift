//
//  ReaderPagedViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Foundation
import AidokuRunner

@MainActor
class ReaderPagedViewModel {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let temporaryPageStore: ReaderTemporaryPageStore?

    var chapter: AidokuRunner.Chapter?
    var pages: [Page] = []

    var preloadedChapter: AidokuRunner.Chapter?
    var preloadedPages: [Page] = []

    private var loadGeneration = 0
    private var preloadGeneration = 0

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        temporaryPageStore: ReaderTemporaryPageStore? = nil
    ) {
        self.source = source
        self.manga = manga
        self.temporaryPageStore = temporaryPageStore
    }

    @discardableResult
    func loadPages(chapter: AidokuRunner.Chapter) async -> Bool {
        loadGeneration += 1
        let generation = loadGeneration

        if preloadedChapter == chapter {
            pages = preloadedPages
            preloadedPages = []
            preloadedChapter = nil
            self.chapter = chapter
            return true
        } else {
            let previousChapter = self.chapter
            let previousPages = pages
            let loadedPages = await getPages(chapter: chapter)

            guard !Task.isCancelled, generation == loadGeneration else { return false }

            // Keep the chapter we are leaving available for an immediate
            // reverse transition. Previously these pages were incorrectly
            // labelled as the destination chapter, which could restore the
            // wrong page list and scrubber when moving backwards quickly.
            if let previousChapter, previousChapter != chapter, !previousPages.isEmpty {
                preloadGeneration += 1
                preloadedChapter = previousChapter
                preloadedPages = previousPages
            }
            self.chapter = chapter
            pages = loadedPages
            return true
        }
    }

    @discardableResult
    func preload(chapter: AidokuRunner.Chapter) async -> [Page] {
        if preloadedChapter == chapter {
            return preloadedPages
        }

        preloadGeneration += 1
        let generation = preloadGeneration
        let loadedPages = await getPages(chapter: chapter)

        guard !Task.isCancelled else { return [] }

        // The caller can safely use its own result even if another adjacent
        // chapter began preloading in the meantime. Only the newest request
        // is allowed to replace the shared one-chapter cache.
        if generation == preloadGeneration {
            preloadedPages = loadedPages
            preloadedChapter = chapter
        }
        return loadedPages
    }

    private func getPages(chapter: AidokuRunner.Chapter) async -> [Page] {
        let sourceId = source?.key ?? manga.sourceKey
        let identifier = ChapterIdentifier(
            sourceKey: sourceId,
            mangaKey: manga.key,
            chapterKey: chapter.key
        )
        let language = chapter.language ?? source?.languages.first
        let isDownloaded = DownloadManager.shared.isChapterDownloaded(chapter: identifier)
        if isDownloaded {
            return await DownloadManager.shared.getDownloadedPages(for: identifier)
                .map {
                    $0.toOld(sourceId: sourceId, chapterId: chapter.key, language: language)
                }
        } else {
            guard var sourcePages = try? await source?.getPageList(
                manga: manga,
                chapter: chapter
            ) else {
                return []
            }

            var pages: [Page] = []
            pages.reserveCapacity(sourcePages.count)

            // iterate in reverse so pages with image data are dropped
            while let sourcePage = sourcePages.popLast() {
                var page = sourcePage.toOld(
                    sourceId: sourceId,
                    chapterId: chapter.key,
                    language: language
                )
                if
                    let temporaryPageStore,
                    let image = page.image,
                    let fileURL = await temporaryPageStore.store(
                        image,
                        chapterKey: chapter.key,
                        pageIndex: sourcePages.count
                    )
                {
                    page.image = nil
                    page.imageURL = fileURL.absoluteString
                }
                pages.append(page)
            }

            return pages.reversed()
        }
    }
}
