//
//  LibraryPagePreviewCache.swift
//  Aidoku
//

import AidokuRunner
import CryptoKit
import ImageIO
import Nuke
import UIKit

struct LibraryPagePreviewTarget: Sendable {
    let manga: AidokuRunner.Manga
    let chapter: AidokuRunner.Chapter
    /// Zero-based page index, matching the cached preview image.
    let pageIndex: Int

    var pageKey: String { "\(chapter.key)|\(pageIndex)" }
}

/// Maintains one persistent current-page preview per Library title and a
/// separate launch-scoped cache for chapter previews shown on manga screens.
/// Images are kept on disk only; the context-menu view owns the sole decoded
/// image while it is visible.
actor LibraryPagePreviewCache {
    static let shared = LibraryPagePreviewCache()

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
    private static let thumbnailDirectory = rootDirectory
        .appendingPathComponent("ReaderThumbnails", isDirectory: true)
    private static let thumbnailCacheLimit: UInt64 = 600 * 1024 * 1024
    private static let thumbnailExpiration: TimeInterval = 30 * 24 * 60 * 60

    private var inFlight: [String: Task<LoadedPreview?, Never>] = [:]
    private var inFlightPages: [String: Task<[Page], Never>] = [:]
    private var pendingRefreshes: [MangaIdentifier: Task<Void, Never>] = [:]
    private var prewarmTask: Task<Void, Never>?
    private var generations: [MangaIdentifier: UInt64] = [:]
    private var resetGeneration: UInt64 = 0
    private var lastThumbnailMaintenanceDate: Date?

    init() {
        Self.persistentDirectory.createDirectory()
        // Termination is not guaranteed on iOS, so launch also clears the
        // cache that is intentionally limited to one app session.
        Self.removeSessionFiles()
        Self.sessionDirectory.createDirectory()
        Self.thumbnailDirectory.createDirectory()
        Self.removeLegacyThumbnailFiles()
        Self.cleanupThumbnailCache()
    }

    /// Returns a prepared current-page preview immediately. A cache miss is
    /// generated once and then occupies the title's single stable disk slot.
    func image(for mangaId: MangaIdentifier) async -> UIImage? {
        if let image = Self.persistentImage(for: mangaId) {
            return image
        }
        return await refreshNow(mangaId: mangaId, returnImage: true)
    }

    /// Describes the chapter and page represented by a Library preview.
    /// Used when the context-menu preview is committed into the reader.
    func target(for mangaId: MangaIdentifier) async -> LibraryPagePreviewTarget? {
        await Self.previewTarget(for: mangaId)
    }

    /// Shares the page-list request with the visible preview, so committing it
    /// does not make the reader fetch the same chapter a second time.
    func pages(for target: LibraryPagePreviewTarget) async -> [Page] {
        let key = "pages|\(target.manga.identifier.description)|\(target.chapter.key)"
        if let task = inFlightPages[key] {
            return await task.value
        }
        let task = Task<[Page], Never> { await Self.loadPages(for: target) }
        inFlightPages[key] = task
        let pages = await task.value
        inFlightPages[key] = nil
        return pages
    }

    /// Returns a launch-scoped preview for a chapter on the manga info screen.
    /// The persistent current-page file is reused when both targets match.
    func image(
        for manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter,
        pageIndex: Int
    ) async -> UIImage? {
        let target = LibraryPagePreviewTarget(manga: manga, chapter: chapter, pageIndex: max(pageIndex, 0))
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
        Self.removeThumbnails(for: mangaId)
    }

    /// Returns a persisted scrubber thumbnail when one has already been
    /// prepared for this exact chapter page.
    func cachedReaderThumbnail(for page: Page, pageIndex: Int, mangaId: MangaIdentifier) async -> UIImage? {
        let url = Self.thumbnailURL(for: page, pageIndex: pageIndex, mangaId: mangaId)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        Self.markThumbnailUsed(url, mangaId: mangaId, chapterKey: page.chapterId)
        enforceThumbnailPolicy(for: mangaId, activeChapterKey: page.chapterId)
        return await image.byPreparingForDisplay() ?? image
    }

    /// Persists a scrubber thumbnail after it has been loaded on demand. This
    /// cache is populated by actual reader use only; it is never prewarmed.
    func storeReaderThumbnail(_ image: UIImage, for page: Page, pageIndex: Int, mangaId: MangaIdentifier) {
        let url = Self.thumbnailURL(for: page, pageIndex: pageIndex, mangaId: mangaId)
        // The URL identity is part of the cache key, so an existing entry is
        // already the exact version required for this page.
        if url.exists {
            Self.markThumbnailUsed(url, mangaId: mangaId, chapterKey: page.chapterId)
            enforceThumbnailPolicy(for: mangaId, activeChapterKey: page.chapterId)
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        url.deletingLastPathComponent().createDirectory()
        try? data.write(to: url, options: .atomic)
        Self.markThumbnailUsed(url, mangaId: mangaId, chapterKey: page.chapterId)
        enforceThumbnailPolicy(for: mangaId, activeChapterKey: page.chapterId)
    }

    /// Removes only the cached variants belonging to a cover whose URL
    /// changed during a library refresh. Covers that did not change remain
    /// untouched.
    func invalidateCoverCache(for url: URL, sourceKey: String) async {
        let source = await SourceManager.shared.source(for: sourceKey)
        var requests: [ImageRequest] = [ImageRequest(urlRequest: URLRequest(url: url))]

        if let fileURL = url.toAidokuFileUrl() {
            requests.append(ImageRequest(urlRequest: URLRequest(url: fileURL)))
        } else if let source {
            let modifiedRequest = await source.getModifiedImageRequest(url: url, context: nil)
            requests.append(ImageRequest(urlRequest: modifiedRequest))

            var processors: [ImageProcessing] = [await CoverDownsampleProcessor(shortestSide: 630)]
            if source.features.processesCovers {
                processors.append(CoverInterceptorProcessor(source: source))
            }
            requests.append(ImageRequest(
                urlRequest: modifiedRequest,
                processors: processors,
                userInfo: [.processesKey: true]
            ))
        }

        for request in requests {
            ImagePipeline.shared.cache.removeCachedImage(for: request)
        }
    }

    /// Prepares the current-page preview for every Library title after a
    /// refresh, matching the original long-press preview behavior. This only
    /// warms the context-menu preview cache; scrubber thumbnails remain
    /// on-demand.
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
        inFlightPages.values.forEach { $0.cancel() }
        inFlightPages.removeAll()
        Self.rootDirectory.removeItem()
        Self.persistentDirectory.createDirectory()
        Self.sessionDirectory.createDirectory()
        Self.thumbnailDirectory.createDirectory()
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
        // Avoid touching the cache when the fetched image is byte-for-byte
        // identical, which also preserves its file timestamp and avoids
        // unnecessary disk writes.
        let existingData = try? Data(contentsOf: urls.image)
        if existingData != loaded.data {
            try? loaded.data.write(to: urls.image, options: .atomic)
        }
        if Self.persistentPageKey(for: mangaId) != loaded.pageKey {
            try? loaded.pageKey.write(to: urls.metadata, atomically: true, encoding: .utf8)
        }
        return returnImage ? loaded.image : nil
    }

    private func load(target: LibraryPagePreviewTarget, taskKey: String) async -> LoadedPreview? {
        if let task = inFlight[taskKey] {
            return await task.value
        }
        let task = Task(priority: .utility) { await self.loadPreview(target: target) }
        inFlight[taskKey] = task
        let result = await task.value
        inFlight[taskKey] = nil
        return result
    }

    private static func previewTarget(for mangaId: MangaIdentifier) async -> LibraryPagePreviewTarget? {
        guard var manga = await CoreDataManager.shared.container.performBackgroundTask({ context in
            CoreDataManager.shared.getManga(mangaId: mangaId, context: context)?.toNewManga()
        }) else { return nil }

        let result = await MangaManager.shared.getNextChapter(mangaId: mangaId)
        guard let chapter = result.nextChapter ?? result.chapters.first else { return nil }
        manga.chapters = result.chapters
        let history = await CoreDataManager.shared.getReadingHistory(mangaId: mangaId)
        let storedPage = history[chapter.id]?.page ?? 1
        return LibraryPagePreviewTarget(
            manga: manga,
            chapter: chapter,
            pageIndex: storedPage > 0 ? storedPage - 1 : 0
        )
    }

    private func loadPreview(target: LibraryPagePreviewTarget) async -> LoadedPreview? {
        let pages = await pages(for: target)
        guard !pages.isEmpty else { return nil }
        let pageIndex = min(max(target.pageIndex, 0), pages.count - 1)
        guard let image = await Self.thumbnail(
            for: pages[pageIndex],
            sourceKey: target.manga.sourceKey,
            width: nil
        ),
              let data = image.pngData() ?? image.jpegData(compressionQuality: 1) else { return nil }
        return LoadedPreview(
            pageKey: "\(target.chapter.key)|\(pageIndex)",
            image: image,
            data: data
        )
    }

    private static func loadPages(for target: LibraryPagePreviewTarget) async -> [Page] {
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

    private static func thumbnail(for page: Page, sourceKey: String, width: CGFloat?) async -> UIImage? {
        if let image = page.image {
            guard let width else { return image }
            return await DownsampleProcessor(width: width).process(image)
        }
        if let zipURLString = page.zipURL,
           let zipURL = URL(string: zipURLString),
           let filePath = page.imageURL {
            let store = ReaderTemporaryPageStore()
            defer { Task { await store.removeAll() } }
            guard let extractedURL = await store.storeArchiveEntry(from: zipURL, path: filePath),
                  let data = try? Data(contentsOf: extractedURL) else { return nil }
            return downsample(data, maxPixelSize: width)
        }
        if let imageURL = page.imageURL, let url = URL(string: imageURL) {
            let source = await SourceManager.shared.source(for: sourceKey)
            var request = await ReaderPageView.imageRequest(url: url, context: page.context, source: source)
            let scale = await UIScreen.main.scale
            if let width {
                request.thumbnail = .init(maxPixelSize: Float(width * scale * 8))
            }
            request.priority = if let width, width <= 48 { .veryLow } else { .low }
            if let width, width <= 48 {
                request.processors.append(await DownsampleProcessor(width: width))
            }
            // Reuse the bounded shared data cache without retaining another
            // decoded image in Nuke's memory cache.
            request.options.insert(.disableMemoryCacheWrites)
            return try? await ImagePipeline.shared.image(for: request)
        }
        if let base64 = page.base64, let data = Data(base64Encoded: base64) {
            return downsample(data, maxPixelSize: width)
        }
        return nil
    }

    private static func downsample(_ data: Data, maxPixelSize: CGFloat?) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [:]
        let image: CGImage?
        if let maxPixelSize {
            options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else {
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

    private static func thumbnailURL(for page: Page, pageIndex: Int, mangaId: MangaIdentifier) -> URL {
        let mangaDirectory = thumbnailDirectory.appendingPathComponent(digest(mangaId.description), isDirectory: true)
        let resourceIdentity = page.thumbnailURL
            ?? page.imageURL
            ?? page.zipURL
            ?? page.base64.map { digest($0) }
            ?? "embedded"
        let contextIdentity = page.context?
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&") ?? ""
        // Including the resource identity makes changed pages naturally use a
        // new file without reading and comparing the previous JPEG.
        // v4 stores the inexpensive 48-pixel strip representation. Keeping
        // the format version in the key prevents older 3x renders from being
        // decoded into memory after this optimization.
        let pageKey = "v4|\(page.chapterId)|\(pageIndex)|\(resourceIdentity)|\(contextIdentity)"
        let chapterDirectory = mangaDirectory
            .appendingPathComponent(digest(page.chapterId), isDirectory: true)
        return chapterDirectory
            .appendingPathComponent(digest(pageKey))
            .appendingPathExtension("jpg")
    }

    private static func removeThumbnails(for mangaId: MangaIdentifier) {
        thumbnailDirectory.appendingPathComponent(digest(mangaId.description), isDirectory: true).removeItem()
    }

    private static func removeLegacyThumbnailFiles() {
        guard let mangaDirectories = try? FileManager.default.contentsOfDirectory(
            at: thumbnailDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for mangaDirectory in mangaDirectories {
            guard
                (try? mangaDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                let files = try? FileManager.default.contentsOfDirectory(
                    at: mangaDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
            else { continue }

            // Previous versions stored the page files directly in the manga
            // directory. The new chapter-aware layout cannot safely associate
            // those files with a chapter, so discard only that legacy level.
            for file in files {
                if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                    file.removeItem()
                }
            }
        }
    }

    private static func markThumbnailUsed(_ url: URL, mangaId: MangaIdentifier, chapterKey: String) {
        let now = Date()
        setModificationDate(now, for: url)
        setModificationDate(now, for: chapterDirectory(for: mangaId, chapterKey: chapterKey))
    }

    private func enforceThumbnailPolicy(for mangaId: MangaIdentifier, activeChapterKey: String) {
        let now = Date()

        let mangaDirectory = Self.thumbnailDirectory
            .appendingPathComponent(Self.digest(mangaId.description), isDirectory: true)
        Self.cleanupExpiredChapterDirectories(in: mangaDirectory, now: now)
        guard let chapterDirectories = Self.chapterDirectories(in: mangaDirectory) else {
            performThumbnailMaintenanceIfNeeded(now: now)
            return
        }

        // Keep the active chapter and the most recently used previous chapter.
        // Directory modification dates are updated on every cache hit/write,
        // so this also survives app restarts without another metadata file.
        let ordered = chapterDirectories.sorted {
            Self.modificationDate(for: $0) > Self.modificationDate(for: $1)
        }
        let activeDirectory = Self.chapterDirectory(
            for: mangaId,
            chapterKey: activeChapterKey
        )
        let retained = Set<URL>([activeDirectory] + Array(ordered.prefix(2)))
        for directory in chapterDirectories where !retained.contains(directory) {
            directory.removeItem()
        }

        performThumbnailMaintenanceIfNeeded(now: now)
    }

    private func performThumbnailMaintenanceIfNeeded(now: Date) {
        guard
            lastThumbnailMaintenanceDate == nil
                || now.timeIntervalSince(lastThumbnailMaintenanceDate!) >= 10
        else { return }
        lastThumbnailMaintenanceDate = now
        Self.cleanupThumbnailCache()
    }

    private static func cleanupThumbnailCache() {
        guard let mangaDirectories = try? FileManager.default.contentsOfDirectory(
            at: thumbnailDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            enforceGlobalThumbnailLimit()
            return
        }
        let now = Date()
        for mangaDirectory in mangaDirectories {
            cleanupExpiredChapterDirectories(in: mangaDirectory, now: now)
        }
        enforceGlobalThumbnailLimit()
    }

    private static func cleanupExpiredChapterDirectories(in mangaDirectory: URL, now: Date) {
        guard let chapters = chapterDirectories(in: mangaDirectory) else { return }
        for chapter in chapters where now.timeIntervalSince(modificationDate(for: chapter)) > thumbnailExpiration {
            chapter.removeItem()
        }
    }

    private static func enforceGlobalThumbnailLimit() {
        struct Entry {
            let url: URL
            let size: UInt64
            let date: Date
        }

        guard let files = allThumbnailFiles() else { return }
        var entries = files.compactMap { url -> Entry? in
            guard
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize,
                let date = values.contentModificationDate
            else { return nil }
            return Entry(url: url, size: UInt64(size), date: date)
        }

        var total = entries.reduce(UInt64(0)) { $0 + $1.size }
        guard total > thumbnailCacheLimit else { return }

        entries.sort { $0.date < $1.date }
        for entry in entries where total > thumbnailCacheLimit {
            entry.url.removeItem()
            total = total > entry.size ? total - entry.size : 0
        }
    }

    private static func allThumbnailFiles() -> [URL]? {
        guard let enumerator = FileManager.default.enumerator(
            at: thumbnailDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        ) else { return nil }
        return enumerator.compactMap { item in
            guard
                let url = item as? URL,
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true,
                url.pathExtension == "jpg"
            else { return nil }
            return url
        }
    }

    private static func chapterDirectories(in mangaDirectory: URL) -> [URL]? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: mangaDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }
        return files.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func chapterDirectory(for mangaId: MangaIdentifier, chapterKey: String) -> URL {
        thumbnailDirectory
            .appendingPathComponent(digest(mangaId.description), isDirectory: true)
            .appendingPathComponent(digest(chapterKey), isDirectory: true)
    }

    private static func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private static func setModificationDate(_ date: Date, for url: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
