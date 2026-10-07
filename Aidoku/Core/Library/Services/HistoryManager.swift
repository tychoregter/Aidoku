//
//  HistoryManager.swift
//  Aidoku
//
//  Created by Skitty on 1/9/23.
//

import AidokuRunner
import CoreData

private final class IncognitoHistoryWriteGate: @unchecked Sendable {
    static let shared = IncognitoHistoryWriteGate()

    private let lock = NSLock()
    private var activeSessions: [MangaIdentifier: Int] = [:]

    func begin(mangaId: MangaIdentifier) {
        lock.lock()
        activeSessions[mangaId, default: 0] += 1
        lock.unlock()
    }

    func end(mangaId: MangaIdentifier) -> Bool {
        lock.lock()
        if let count = activeSessions[mangaId] {
            if count <= 1 {
                activeSessions.removeValue(forKey: mangaId)
            } else {
                activeSessions[mangaId] = count - 1
            }
        }
        let hasActiveSession = activeSessions[mangaId] != nil
        lock.unlock()
        return !hasActiveSession
    }

    func contains(mangaId: MangaIdentifier) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeSessions[mangaId] != nil
    }
}

final class HistoryManager: Sendable {
    static let shared = HistoryManager()

    func beginIncognitoSession(mangaId: MangaIdentifier) {
        IncognitoHistoryWriteGate.shared.begin(mangaId: mangaId)
    }

    func endIncognitoSession(mangaId: MangaIdentifier) {
        guard IncognitoHistoryWriteGate.shared.end(mangaId: mangaId) else { return }
        Task {
            await TrackerManager.shared.processPendingUpdates()
        }
    }

    func isIncognitoSessionActive(mangaId: MangaIdentifier) -> Bool {
        IncognitoHistoryWriteGate.shared.contains(mangaId: mangaId)
    }

    private func isUpdateAllowed(for mangaId: MangaIdentifier) async -> Bool {
        guard !isIncognitoSessionActive(mangaId: mangaId) else { return false }
        let allowed: Bool
        if AppSettings.tracking.onlyUpdateLibraryItems.get() {
            allowed = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.hasLibraryManga(mangaId: mangaId, context: context)
            }
        } else {
            allowed = true
        }
        // Recheck after the async library lookup in case an incognito reader
        // for this title was opened while that lookup was suspended.
        return allowed && !isIncognitoSessionActive(mangaId: mangaId)
    }
}

extension HistoryManager {
    func setProgress(
        chapterId: ChapterIdentifier,
        chapter: AidokuRunner.Chapter,
        progress: Int,
        totalPages: Int? = nil,
        scrollPosition: Double? = nil,
        completed: Bool
    ) async {
        let mangaId = chapterId.mangaIdentifier
        guard await isUpdateAllowed(for: mangaId) else { return }
        let didSave = await CoreDataManager.shared.container.performBackgroundTask { context in
            guard !self.isIncognitoSessionActive(mangaId: mangaId) else { return false }
            CoreDataManager.shared.setRead(mangaId: mangaId, context: context)
            CoreDataManager.shared.setProgress(
                progress,
                chapterId: chapterId,
                totalPages: totalPages,
                scrollPosition: scrollPosition,
                context: context
            )
            do {
                try context.save()
                return true
            } catch {
                LogManager.logger.error("HistoryManager.setProgress: \(error)")
                return false
            }
        }
        guard didSave else { return }
        NotificationCenter.default.post(name: .historySet, object: (chapterId, progress))
        await LibraryPagePreviewCache.shared.invalidate(mangaId: mangaId)
        await CoverPalette.persistIfEligible(mangaId)
        if !completed {
            Task {
                // update page trackers with progress
                await TrackerManager.shared.setProgress(
                    mangaId: mangaId,
                    chapter: chapter,
                    progress: .init(completed: false, page: progress)
                )
            }
        }
    }

    struct ReadingSessionData {
        let startDate: Date
        let endDate: Date
        let pagesRead: Int
    }

    func addSession(chapterId: ChapterIdentifier, data: ReadingSessionData) async {
        guard await isUpdateAllowed(for: chapterId.mangaIdentifier) else { return }
        await CoreDataManager.shared.container.performBackgroundTask { context in
            guard !self.isIncognitoSessionActive(mangaId: chapterId.mangaIdentifier) else { return }
            CoreDataManager.shared.createSession(
                chapterId: chapterId,
                data: data,
                context: context
            )
            do {
                try context.save()
            } catch {
                LogManager.logger.error("HistoryManager.addSession: \(error)")
            }
        }
    }

    func addHistory(
        mangaId: MangaIdentifier,
        chapters: [AidokuRunner.Chapter],
        date: Date = Date(),
        skipTracker: Tracker? = nil
    ) async {
        guard await isUpdateAllowed(for: mangaId) else { return }
        // mark each manga as read
        let success = await CoreDataManager.shared.container.performBackgroundTask { context in
            guard !self.isIncognitoSessionActive(mangaId: mangaId) else { return false }
            // mark chapters as read
            let success = CoreDataManager.shared.setCompleted(
                chapterIds: chapters.map {
                    .init(sourceKey: mangaId.sourceKey, mangaKey: mangaId.mangaKey, chapterKey: $0.key)
                },
                date: date,
                context: context
            )
            if success {
                CoreDataManager.shared.setRead(
                    mangaId: mangaId,
                    date: date,
                    context: context
                )
                do {
                    try context.save()
                } catch {
                    LogManager.logger.error("HistoryManager.addHistory: \(error.localizedDescription)")
                }
            }
            return success
        }
        guard success else { return }
        await LibraryPagePreviewCache.shared.invalidate(mangaId: mangaId)
        await CoverPalette.persistIfEligible(mangaId)
        NotificationCenter.default.post(
            name: .historyAdded,
            object: chapters.map {
                ChapterIdentifier(sourceKey: mangaId.sourceKey, mangaKey: mangaId.mangaKey, chapterKey: $0.key)
            }
        )
        Task {
            if AppSettings.tracking.updateAfterReading.get() {
                // update tracker with chapter with largest number
                if let maxChapter = chapters.max(by: { $0.chapterNumber ?? 0 < $1.chapterNumber ?? 0 }) {
                    await TrackerManager.shared.setCompleted(
                        mangaId: mangaId,
                        chapter: maxChapter,
                        skipTracker: skipTracker
                    )
                }
            }

            await TrackerManager.shared.setProgress(
                mangaId: mangaId,
                chapters: chapters,
                progress: .init(completed: true, page: 0)
            )
        }
    }

    func removeHistory(chapterIds: [ChapterIdentifier]) async {
        guard !chapterIds.isEmpty else { return }
        await CoreDataManager.shared.removeHistory(chapterIds: chapterIds)
        await LibraryPagePreviewCache.shared.invalidate(mangaId: chapterIds[0].mangaIdentifier)
        for identifier in Set(chapterIds.map(\.mangaIdentifier)) {
            await CoverPalette.reconcile(identifier)
        }
        NotificationCenter.default.post(name: .historyRemoved, object: chapterIds)
        Task {
            await TrackerManager.shared.setProgress(
                mangaId: chapterIds[0].mangaIdentifier,
                chapters: chapterIds.map { .init(key: $0.chapterKey) },
                progress: .init(completed: false, page: 0)
            )
        }
    }

    func removeHistory(mangaId: MangaIdentifier) async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removeHistory(mangaId: mangaId, context: context)
            try? context.save()
        }
        await LibraryPagePreviewCache.shared.invalidate(mangaId: mangaId)
        await CoverPalette.reconcile(mangaId)
        NotificationCenter.default.post(name: .historyRemoved, object: mangaId)
        Task {
            let chapters = await CoreDataManager.shared.getChapters(mangaId: mangaId)
            await TrackerManager.shared.setProgress(
                mangaId: mangaId,
                chapters: chapters.map { $0.toNew() },
                progress: .init(completed: false, page: 0)
            )
        }
    }
}
