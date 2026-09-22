//
//  KomgaLibraryProgressSyncCoordinator.swift
//  Aidoku
//

import Foundation

/// Synchronizes progress for every Komga title in the library by server instead
/// of issuing a complete book-list request for each individual series.
actor KomgaLibraryProgressSyncCoordinator {
    static let shared = KomgaLibraryProgressSyncCoordinator()

    enum SyncTrigger: Sendable {
        case appLaunch
        case appActivation
        case libraryRefresh
    }

    /// Kill switch kept intentionally local so the new implementation can be
    /// disabled or reverted without touching the existing tracker behavior.
    nonisolated static let isEnabled = true

    private var isSyncing = false
    private let lastSyncDateKey = "Tracking.komgaLastProgressSyncDate"

    func syncIfNeeded(trigger: SyncTrigger = .appActivation) async {
        guard Self.isEnabled, !isSyncing else { return }

        let interval = AppSettings.tracking.komgaProgressSyncInterval.get()
        let isLibraryRefresh = trigger == .libraryRefresh
        if !isLibraryRefresh {
            if interval.timeInterval == nil, trigger != .appLaunch {
                return
            }
            if let lastSyncDate,
               let gracePeriod = interval.timeInterval,
               Date().timeIntervalSince(lastSyncDate) < gracePeriod {
                return
            }
        }

        if !isLibraryRefresh, interval == .appLaunchAndRefresh,
           trigger != .appLaunch {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        let links = await loadLibraryLinks()
        guard !links.isEmpty else {
            recordSyncDate()
            return
        }

        let linksBySource = Dictionary(grouping: links, by: \.sourceKey)
        var progressByManga: [MangaIdentifier: [String: ChapterReadProgress]] = [:]
        var didSyncAnySource = false

        for (sourceKey, sourceLinks) in linksBySource {
            guard KomgaTracker.isTrackingEnabled(for: sourceKey) else { continue }
            do {
                let seriesIds = Set(sourceLinks.map(\.seriesId))
                let sourceProgress = try await TrackerManager.komga.getLibraryProgress(
                    sourceKey: sourceKey,
                    seriesIds: seriesIds,
                    forceRefresh: isLibraryRefresh
                )
                guard KomgaTracker.isTrackingEnabled(for: sourceKey) else { continue }
                didSyncAnySource = true
                for link in sourceLinks {
                    guard let progress = sourceProgress[link.seriesId], !progress.isEmpty else { continue }
                    progressByManga[link.mangaId] = progress
                }
            } catch {
                LogManager.logger.error("Failed to bulk sync Komga progress for \(sourceKey): \(error)")
            }
        }

        guard didSyncAnySource else {
            return
        }
        progressByManga = progressByManga.filter {
            KomgaTracker.isTrackingEnabled(for: $0.key.sourceKey)
        }
        await TrackerManager.shared.applyPageTrackerHistory(
            progressByManga,
            refreshLibrary: true,
            respectKomgaTrackingSetting: true
        )
        recordSyncDate()
    }
}

private extension KomgaLibraryProgressSyncCoordinator {
    var lastSyncDate: Date? {
        guard let timestamp = UserDefaults.standard.object(forKey: lastSyncDateKey) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    func recordSyncDate() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncDateKey)
    }

    struct LibraryLink: Sendable {
        let sourceKey: String
        let seriesId: String
        let mangaId: MangaIdentifier
    }

    func loadLibraryLinks() async -> [LibraryLink] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let libraryIds = Set(
                CoreDataManager.shared.getLibraryManga(context: context).compactMap { $0.manga?.identifier }
            )
            return CoreDataManager.shared.getTracks(trackerId: TrackerManager.komga.id, context: context)
                .compactMap { track -> LibraryLink? in
                    guard
                        let sourceKey = track.sourceId,
                        let seriesId = track.mangaId
                    else { return nil }
                    guard KomgaTracker.isTrackingEnabled(for: sourceKey) else { return nil }
                    let mangaId = MangaIdentifier(sourceKey: sourceKey, mangaKey: seriesId)
                    guard libraryIds.contains(mangaId) else { return nil }
                    return .init(sourceKey: sourceKey, seriesId: seriesId, mangaId: mangaId)
                }
        }
    }
}
