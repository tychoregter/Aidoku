//
//  LibraryPagePreviewCache.swift
//  Aidoku
//

import AidokuRunner
import CryptoKit
import ImageIO
import Nuke
import UIKit

/// Maintains one persistent current-page preview per Library title and a
/// separate launch-scoped cache for chapter previews shown on manga screens.
/// Images are kept on disk only; the context-menu view owns the sole decoded
/// image while it is visible.
actor LibraryPagePreviewCache {
    static let shared = LibraryPagePreviewCache()

    private struct PreviewTarget: Sendable {
        let manga: AidokuRunner.Manga
        let chapter: AidokuRunner.Chapter
        let pageIndex: Int

        var pageKey: String { "\(chapter.key)|\(pageIndex)" }
    }

    private struct LoadedPreview {
        let pageKey: String
        let image: UIImage
        let data: Data
    }

    private static let rootDirectory = FileManager.default.cachesDirectory
        .appendingPathComponent("LibraryPagePreviews", isDirectory: true)
    private static let persistentDirectory = rootDirectory
        .appendingPathComponent("CurrentPages", isDirectory: true)
    private static let sessionDirectory = rootDirectory
        .appendingPathComponent("ChapterPreviews", isDirectory: true)
    private static let thumbnailOptions = ImageRequest.ThumbnailOptions(maxPixelSize: 1200)

    private var inFlight: [String: Task<LoadedPreview?, Never>] = [:]
    private var pendingRefreshes: [MangaIdentifier: Task<Void, Never>] = [:]
    private var prewarmTask: Task<Void, Never>?
    private var generations: [MangaIdentifier: UInt64] = [:]
    private var resetGeneration: UInt64 = 0

    init() {
        Self.persistentDirectory.createDirectory()
        // Termination is not guaranteed on iOS, so launch also clears the
        // cache that is intentionally limited to one app session.
        Self.removeSessionFiles()
        Self.sessionDirectory.createDirectory()
    }

    /// Returns a prepared current-page preview immediately. A cache miss is
    /// generated once and then occupies the title's single stable disk slot.
    func image(for mangaId: MangaIdentifier) async -> UIImage? {
        if let image = Self.persistentImage(for: mangaId) {
            return image
        }
        return await refreshNow(mangaId: mangaId, returnImage: true)
    }

    /// Returns a launch-scoped preview for a chapter on the manga info screen.
    /// The persistent current-page file is reused when both targets match.
    func image(
        for manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter,
        pageIndex: Int
    ) async -> UIImage? {
        let target = PreviewTarget(manga: manga, chapter: chapter, pageIndex: max(pageIndex, 0))
        let mangaId = manga.identifier
        if Self.persistentPageKey(for: mangaId) == target.pageKey,
           let image = Self.persistentImage(for: mangaId) {
            return image
        }

        let key = "chapter|\(mangaId.description)|\(target.pageKey)"
        let url = Self.sessionDirectory
            .appendingPathComponent(Self.digest(key))
            .appendingPathExtension("jpg")
        if let image = UIImage(contentsOfFile: url.path) {
            return image
        }

        let currentResetGeneration = resetGeneration
        let loaded = await load(target: target, taskKey: key)
        guard let loaded, currentResetGeneration == resetGeneration else { return nil }
        try? loaded.data.write(to: url, options: .atomic)
        return loaded.image
    }

    /// Debounces reader progress writes, then replaces the persistent preview
    /// only when its chapter/page identity changed.
    func invalidate(mangaId: MangaIdentifier) {
        generations[mangaId, default: 0] &+= 1
        pendingRefreshes[mangaId]?.cancel()
        pendingRefreshes[mangaId] = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled, let self else { return }
            _ = await self.refreshNow(mangaId: mangaId, returnImage: false)
            await self.clearPendingRefresh(for: mangaId)
        }
    }

    /// Removes every trace of a title when it leaves the Library.
    func remove(mangaId: MangaIdentifier) {
        generations[mangaId, default: 0] &+= 1
        pendingRefreshes[mangaId]?.cancel()
        pendingRefreshes[mangaId] = nil
        let taskKey = Self.persistentTaskKey(for: mangaId)
        inFlight[taskKey]?.cancel()
        inFlight[taskKey] = nil
        Self.removePersistentFiles(for: mangaId)
    }

    /// Serial work prevents a large Library from decoding many pages at once.
    func prewarmLibrary() async {
        guard AppSettings.library.contextMenuPagePreviews.get() else { return }
        if let prewarmTask {
            await prewarmTask.value
            return
        }

        let task = Task(priority: .utility) { [weak self] in
            let mangaIds = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getLibraryManga(context: context).compactMap { object in
                    object.manga?.toManga().identifier
                }
            }
            Self.removeOrphanedPersistentFiles(keeping: Set(mangaIds))
            guard let self else { return }
            for mangaId in mangaIds {
                guard !Task.isCancelled else { return }
                _ = await self.refreshNow(mangaId: mangaId, returnImage: false)
            }
        }
        prewarmTask = task
        await task.value
        prewarmTask = nil
    }

    func removeAll() {
        resetGeneration &+= 1
        prewarmTask?.cancel()
        prewarmTask = nil
        pendingRefreshes.values.forEach { $0.cancel() }
        pendingRefreshes.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        Self.rootDirectory.removeItem()
        Self.persistentDirectory.createDirectory()
        Self.sessionDirectory.createDirectory()
    }

    /// Synchronous so cleanup can complete in the short termination window.
    nonisolated static func removeSessionFiles() {
        sessionDirectory.removeItem()
    }

    private func clearPendingRefresh(for mangaId: MangaIdentifier) {
        pendingRefreshes[mangaId] = nil
    }

    private func refreshNow(mangaId: MangaIdentifier, returnImage: Bool) async -> UIImage? {
        guard let target = await Self.previewTarget(for: mangaId) else {
            Self.removePersistentFiles(for: mangaId)
            return nil
        }

        let urls = Self.persistentURLs(for: mangaId)
        if Self.persistentPageKey(for: mangaId) == target.pageKey, urls.image.exists {
            return returnImage ? UIImage(contentsOfFile: urls.image.path) : nil
        }

        let currentGeneration = generations[mangaId, default: 0]
        let currentResetGeneration = resetGeneration
        let loaded = await load(target: target, taskKey: Self.persistentTaskKey(for: mangaId))
        guard
            let loaded,
            currentGeneration == generations[mangaId, default: 0],
            currentResetGeneration == resetGeneration
        else { return nil }

        // Keep the old preview usable until the complete replacement is ready.
        try? loaded.data.write(to: urls.image, options: .atomic)
        try? loaded.pageKey.write(to: urls.metadata, atomically: true, encoding: .utf8)
        return returnImage ? loaded.image : nil
    }

    private func load(target: PreviewTarget, taskKey: String) async -> LoadedPreview? {
        if let task = inFlight[taskKey] {
            return await task.value
        }
        let task = Task(priority: .utility) { await Self.loadPreview(target: target) }
        inFlight[taskKey] = task
        let result = await task.value
        inFlight[taskKey] = nil
        return result
    }

    private static func previewTarget(for mangaId: MangaIdentifier) async -> PreviewTarget? {
        guard let manga = await CoreDataManager.shared.container.performBackgroundTask({ context in
            CoreDataManager.shared.getManga(mangaId: mangaId, context: context)?.toNewManga()
        }) else { return nil }

        let result = await MangaManager.shared.getNextChapter(mangaId: mangaId)
        guard let chapter = result.nextChapter ?? result.chapters.first else { return nil }
        let history = await CoreDataManager.shared.getReadingHistory(mangaId: mangaId)
        let storedPage = history[chapter.id]?.page ?? 1
        return PreviewTarget(
            manga: manga,
            chapter: chapter,
            pageIndex: storedPage > 0 ? storedPage - 1 : 0
        )
    }

    private static func loadPreview(target: PreviewTarget) async -> LoadedPreview? {
        let pages = await pages(for: target)
        guard !pages.isEmpty else { return nil }
        let pageIndex = min(max(target.pageIndex, 0), pages.count - 1)
        guard let image = await thumbnail(for: pages[pageIndex], sourceKey: target.manga.sourceKey),
              let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        return LoadedPreview(
            pageKey: "\(target.chapter.key)|\(pageIndex)",
            image: image,
            data: data
        )
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
            return image.preparingThumbnail(of: CGSize(width: 1200, height: 1200)) ?? image
        }
        if let zipURLString = page.zipURL,
           let zipURL = URL(string: zipURLString),
           let filePath = page.imageURL {
            let store = ReaderTemporaryPageStore()
            defer { Task { await store.removeAll() } }
            guard let extractedURL = await store.storeArchiveEntry(from: zipURL, path: filePath),
                  let data = try? Data(contentsOf: extractedURL) else { return nil }
            return downsample(data)
        }
        if let imageURL = page.imageURL, let url = URL(string: imageURL) {
            let source = await SourceManager.shared.source(for: sourceKey)
            var request = await ReaderPageView.imageRequest(url: url, context: page.context, source: source)
            request.thumbnail = thumbnailOptions
            request.priority = .low
            // Reuse the bounded shared data cache without retaining another
            // decoded image in Nuke's memory cache.
            request.options.insert(.disableMemoryCacheWrites)
            return try? await ImagePipeline.shared.image(for: request)
        }
        if let base64 = page.base64, let data = Data(base64Encoded: base64) {
            return downsample(data)
        }
        return nil
    }

    private static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private static func persistentImage(for mangaId: MangaIdentifier) -> UIImage? {
        let urls = persistentURLs(for: mangaId)
        guard urls.metadata.exists, urls.image.exists else { return nil }
        return UIImage(contentsOfFile: urls.image.path)
    }

    private static func persistentPageKey(for mangaId: MangaIdentifier) -> String? {
        try? String(contentsOf: persistentURLs(for: mangaId).metadata, encoding: .utf8)
    }

    private static func removePersistentFiles(for mangaId: MangaIdentifier) {
        let urls = persistentURLs(for: mangaId)
        urls.image.removeItem()
        urls.metadata.removeItem()
    }

    private static func removeOrphanedPersistentFiles(keeping mangaIds: Set<MangaIdentifier>) {
        let validNames = Set(mangaIds.map { digest($0.description) })
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: persistentDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !validNames.contains(file.deletingPathExtension().lastPathComponent) {
            file.removeItem()
        }
    }

    private static func persistentTaskKey(for mangaId: MangaIdentifier) -> String {
        "current|\(mangaId.description)"
    }

    private static func persistentURLs(for mangaId: MangaIdentifier) -> (image: URL, metadata: URL) {
        let name = digest(mangaId.description)
        return (
            persistentDirectory.appendingPathComponent(name).appendingPathExtension("jpg"),
            persistentDirectory.appendingPathComponent(name).appendingPathExtension("txt")
        )
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
