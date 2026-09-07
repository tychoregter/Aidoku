//
//  LibraryPagePreviewCache.swift
//  Aidoku
//

import AidokuRunner
import CryptoKit
import Nuke
import UIKit

/// Stores one low-resolution context-menu preview for each Library title.
/// The cache key includes the chapter and page, so advancing in the reader
/// replaces the old preview instead of leaving stale pages on disk.
actor LibraryPagePreviewCache {
    static let shared = LibraryPagePreviewCache()

    private struct MemoryEntry {
        let pageKey: String
        let image: UIImage
    }

    private struct LoadedPreview {
        let pageKey: String
        let image: UIImage
    }

    private static let directory = FileManager.default.cachesDirectory
        .appendingPathComponent("LibraryPagePreviews", isDirectory: true)
    private static let thumbnailOptions = ImageRequest.ThumbnailOptions(maxPixelSize: 1200)

    private var memoryEntries: [MangaIdentifier: MemoryEntry] = [:]
    private var preparedPageKeys: [MangaIdentifier: String] = [:]
    private var inFlight: [MangaIdentifier: Task<LoadedPreview?, Never>] = [:]

    init() {
        Self.directory.createDirectory()
    }

    func image(for mangaId: MangaIdentifier) async -> UIImage? {
        guard let target = await Self.previewTarget(for: mangaId) else { return nil }
        if let entry = memoryEntries[mangaId], entry.pageKey == target.pageKey {
            return entry.image
        }
        if let task = inFlight[mangaId] {
            return await task.value?.image
        }

        let task = Task(priority: .userInitiated) {
            await Self.loadPreview(for: mangaId, target: target)
        }
        inFlight[mangaId] = task
        let result = await task.value
        inFlight[mangaId] = nil

        if let result {
            memoryEntries[mangaId] = MemoryEntry(pageKey: result.pageKey, image: result.image)
            preparedPageKeys[mangaId] = result.pageKey
        }
        return result?.image
    }

    /// Warms previews serially at utility priority to avoid flooding a source
    /// with page-list and image requests when a large Library first appears.
    func prewarm(_ mangaIds: [MangaIdentifier]) async {
        guard AppSettings.library.contextMenuPagePreviews.get() else { return }
        for mangaId in mangaIds {
            guard !Task.isCancelled else { return }
            guard let target = await Self.previewTarget(for: mangaId) else { continue }
            if preparedPageKeys[mangaId] == target.pageKey || memoryEntries[mangaId]?.pageKey == target.pageKey {
                continue
            }
            _ = await image(for: mangaId)
        }
    }

    func invalidate(mangaId: MangaIdentifier) {
        inFlight[mangaId]?.cancel()
        inFlight[mangaId] = nil
        memoryEntries[mangaId] = nil
        preparedPageKeys[mangaId] = nil
        Self.removeFiles(for: mangaId)
    }

    private struct PreviewTarget: Sendable {
        let manga: AidokuRunner.Manga
        let chapter: AidokuRunner.Chapter
        let pageIndex: Int

        var pageKey: String {
            "\(chapter.key)|\(pageIndex)"
        }
    }

    private static func previewTarget(for mangaId: MangaIdentifier) async -> PreviewTarget? {
        guard let manga = await CoreDataManager.shared.container.performBackgroundTask({ context in
            CoreDataManager.shared.getManga(mangaId: mangaId, context: context)?.toNewManga()
        }) else {
            return nil
        }

        let result = await MangaManager.shared.getNextChapter(mangaId: mangaId)
        guard let chapter = result.nextChapter ?? result.chapters.first else { return nil }
        let history = await CoreDataManager.shared.getReadingHistory(mangaId: mangaId)
        let storedPage = history[chapter.id]?.page ?? 1
        let pageIndex = storedPage > 0 ? storedPage - 1 : 0
        return PreviewTarget(manga: manga, chapter: chapter, pageIndex: pageIndex)
    }

    private static func loadPreview(for mangaId: MangaIdentifier, target: PreviewTarget) async -> LoadedPreview? {
        if let cached = cachedImage(for: mangaId, pageKey: target.pageKey) {
            return LoadedPreview(pageKey: target.pageKey, image: cached)
        }

        let pages = await pages(for: target)
        guard !pages.isEmpty else { return nil }
        let pageIndex = min(max(target.pageIndex, 0), pages.count - 1)
        let pageKey = "\(target.chapter.key)|\(pageIndex)"

        if pageKey != target.pageKey, let cached = cachedImage(for: mangaId, pageKey: pageKey) {
            return LoadedPreview(pageKey: pageKey, image: cached)
        }
        guard let image = await thumbnail(for: pages[pageIndex], sourceKey: mangaId.sourceKey) else { return nil }
        store(image: image, for: mangaId, pageKey: pageKey)
        return LoadedPreview(pageKey: pageKey, image: image)
    }

    private static func pages(for target: PreviewTarget) async -> [Page] {
        let mangaId = target.manga.identifier
        let chapterId = ChapterIdentifier(
            sourceKey: mangaId.sourceKey,
            mangaKey: mangaId.mangaKey,
            chapterKey: target.chapter.key
        )
        let source = await SourceManager.shared.source(for: mangaId.sourceKey)
        let language = target.chapter.language ?? source?.languages.first

        if await DownloadManager.shared.isChapterDownloaded(chapter: chapterId) {
            return await DownloadManager.shared.getDownloadedPages(for: chapterId).map {
                $0.toOld(sourceId: mangaId.sourceKey, chapterId: target.chapter.key, language: language)
            }
        }

        guard let source,
              let sourcePages = try? await source.getPageList(manga: target.manga, chapter: target.chapter) else {
            return []
        }
        return sourcePages.map {
            $0.toOld(sourceId: mangaId.sourceKey, chapterId: target.chapter.key, language: language)
        }
    }

    private static func thumbnail(for page: Page, sourceKey: String) async -> UIImage? {
        if let image = page.image {
            return image.preparingThumbnail(of: CGSize(width: 900, height: 1200)) ?? image
        }

        if let zipURLString = page.zipURL,
           let zipURL = URL(string: zipURLString),
           let filePath = page.imageURL {
            let store = ReaderTemporaryPageStore()
            defer { Task { await store.removeAll() } }
            guard let extractedURL = await store.storeArchiveEntry(from: zipURL, path: filePath),
                  let data = try? Data(contentsOf: extractedURL) else { return nil }
            return thumbnailOptions.makeThumbnail(with: data)
        }

        if let imageURL = page.imageURL, let url = URL(string: imageURL) {
            let source = await SourceManager.shared.source(for: sourceKey)
            var request = await ReaderPageView.imageRequest(url: url, context: page.context, source: source)
            request.thumbnail = thumbnailOptions
            request.priority = .low
            return try? await ImagePipeline.shared.image(for: request)
        }

        if let base64 = page.base64, let data = Data(base64Encoded: base64) {
            return thumbnailOptions.makeThumbnail(with: data)
        }
        return nil
    }

    private static func cachedImage(for mangaId: MangaIdentifier, pageKey: String) -> UIImage? {
        let urls = cacheURLs(for: mangaId)
        guard (try? String(contentsOf: urls.metadata, encoding: .utf8)) == pageKey else {
            removeFiles(for: mangaId)
            return nil
        }
        return UIImage(contentsOfFile: urls.image.path)
    }

    private static func store(image: UIImage, for mangaId: MangaIdentifier, pageKey: String) {
        let urls = cacheURLs(for: mangaId)
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        try? data.write(to: urls.image, options: .atomic)
        try? pageKey.write(to: urls.metadata, atomically: true, encoding: .utf8)
    }

    private static func removeFiles(for mangaId: MangaIdentifier) {
        let urls = cacheURLs(for: mangaId)
        urls.image.removeItem()
        urls.metadata.removeItem()
    }

    private static func cacheURLs(for mangaId: MangaIdentifier) -> (image: URL, metadata: URL) {
        let value = "\(mangaId.sourceKey)\u{0}\(mangaId.mangaKey)"
        let digest = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return (
            directory.appendingPathComponent(digest).appendingPathExtension("jpg"),
            directory.appendingPathComponent(digest).appendingPathExtension("txt")
        )
    }
}
