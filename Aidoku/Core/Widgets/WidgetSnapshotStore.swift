//
//  WidgetSnapshotStore.swift
//  Aidoku
//

import CoreData
import Foundation
import ImageIO
import UIKit
import WidgetKit
import AidokuRunner

struct AidokuWidgetItem: Codable, Hashable, Sendable {
    let sourceKey: String
    let mangaKey: String
    let title: String
    let coverURL: String?
    let coverFilename: String?
    let position: String?
    let volume: String?
    let pagesLeft: Int?
    let atVolumeStart: Bool
    let completionStatus: String?
    let unreadCount: Int
    let contentRating: Int
    let lastRead: Date?
    let lastOpened: Date?
    let lastUpdated: Date?
    let dateAdded: Date
    let lastChapter: Date?
    let totalChapters: Int

    var id: String { "\(sourceKey).\(mangaKey)" }
}

struct AidokuWidgetSnapshot: Codable, Sendable {
    let updatedAt: Date
    let groups: [String: [AidokuWidgetItem]]
}

enum AidokuWidgetSnapshotStore {
    static let appGroupIdentifier = "group.io.orangebyte.Aidoku"
    private static let snapshotFilename = "library-widget-snapshot.json"

    private static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(snapshotFilename)
    }

    static func update() async {
        let snapshot = await CoreDataManager.shared.container.performBackgroundTask { context in
            makeSnapshot(context: context)
        }
        let cachedSnapshot = await cacheCovers(in: snapshot)
        guard let url = snapshotURL, let data = try? JSONEncoder().encode(cachedSnapshot) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func makeSnapshot(context: NSManagedObjectContext) -> AidokuWidgetSnapshot {
        let favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: "library.favoriteMangaIdentifiers") ?? [])
        let request = LibraryMangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "manga != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "manga.title", ascending: true)]
        let objects = (try? context.fetch(request)) ?? []

        var groups = Dictionary(uniqueKeysWithValues: [
            "all", "favorites", "started", "unread", "completed", "updatedChapters"
        ].map { ($0, [AidokuWidgetItem]()) })

        for libraryObject in objects {
            guard let manga = libraryObject.manga else { continue }
            let identifier = manga.identifier
            let unreadCount = CoreDataManager.shared.unreadCount(
                mangaId: identifier,
                lang: nil,
                scanlators: nil,
                context: context
            )
            let history = CoreDataManager.shared.getHistoryForManga(mangaId: identifier, context: context)
                .sorted { ($0.dateRead ?? .distantPast) > ($1.dateRead ?? .distantPast) }
            let latestHistory = history.first
            let historyChapter = latestHistory?.chapter ?? latestHistory.flatMap {
                CoreDataManager.shared.getChapter(
                    chapterId: ChapterIdentifier(
                        sourceKey: identifier.sourceKey,
                        mangaKey: identifier.mangaKey,
                        chapterKey: $0.chapterId
                    ),
                    context: context
                )
            }
            let chapters = (manga.chapters?.allObjects as? [ChapterObject]) ?? []
            let currentChapter = historyChapter ?? chapters.min { $0.sourceOrder < $1.sourceOrder }
            let position = currentChapter.flatMap { chapter in
                if let volume = chapter.volume, let number = chapter.chapter {
                    return "Chapter \(volume), Chapter \(number)"
                }
                if let volume = chapter.volume { return "Chapter \(volume)" }
                if let number = chapter.chapter { return "Chapter \(number)" }
                return chapter.title
            }
            let finalChapter = chapters.max { $0.sourceOrder < $1.sourceOrder }
            let isFinalChapter = currentChapter != nil && currentChapter?.sourceOrder == finalChapter?.sourceOrder
            // A title without history starts at its first chapter. Treat that
            // as volume 1 when the source does not provide an explicit volume,
            // so the widget still has a useful start-status string.
            let volume = currentChapter?.volume?.stringValue ?? (latestHistory == nil && currentChapter != nil ? "1" : nil)
            // Store the current volume's progress as a percentage. The field
            // name is retained so existing widget snapshots remain decodable.
            let pagesLeft: Int? = latestHistory.flatMap { history in
                guard history.total > 0 else { return nil }
                let percentage = (Double(history.progress) / Double(history.total) * 100).rounded()
                return min(max(Int(percentage), 0), 100)
            }
            let completionStatus: String? = if latestHistory?.completed == true && isFinalChapter {
                manga.status == AidokuRunner.PublishingStatus.completed.rawValue ? "Finished" : "Caught Up"
            } else { nil }
            let item = AidokuWidgetItem(
                sourceKey: identifier.sourceKey,
                mangaKey: identifier.mangaKey,
                title: manga.title,
                coverURL: manga.cover,
                coverFilename: manga.cover.flatMap { coverFilename(for: identifier.description, url: $0) },
                position: position,
                volume: volume,
                pagesLeft: pagesLeft,
                atVolumeStart: (latestHistory?.progress ?? 0) <= 1,
                completionStatus: completionStatus,
                unreadCount: unreadCount,
                contentRating: Int(manga.nsfw),
                lastRead: libraryObject.lastRead,
                lastOpened: libraryObject.lastOpened,
                lastUpdated: libraryObject.lastUpdated,
                dateAdded: libraryObject.dateAdded,
                lastChapter: libraryObject.lastChapter,
                totalChapters: manga.chapters?.count ?? 0
            )

            groups["all", default: []].append(item)
            if favoriteIDs.contains(identifier.description) { groups["favorites", default: []].append(item) }
            if !history.isEmpty { groups["started", default: []].append(item) }
            if unreadCount > 0 { groups["unread", default: []].append(item) }
            if manga.status == AidokuRunner.PublishingStatus.completed.rawValue { groups["completed", default: []].append(item) }
            if libraryObject.lastUpdatedChapters > libraryObject.lastOpened {
                groups["updatedChapters", default: []].append(item)
            }
        }

        return AidokuWidgetSnapshot(updatedAt: .now, groups: groups)
    }

    private static func coverFilename(for identifier: String, url: String) -> String {
        let safeIdentifier = Data(identifier.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let safeURL = Data(url.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "cover-\(safeIdentifier)-\(safeURL).jpg"
    }

    private static func cacheCovers(in snapshot: AidokuWidgetSnapshot) async -> AidokuWidgetSnapshot {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("WidgetCovers", isDirectory: true) else { return snapshot }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let items = Set(snapshot.groups.values.flatMap { $0 })
        let validFilenames = Set(items.compactMap(\.coverFilename))
        if let cachedFiles = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in cachedFiles where !validFilenames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        for item in items {
            guard let urlString = item.coverURL,
                  let url = URL(string: urlString),
                  let filename = item.coverFilename else { continue }
            let destination = directory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: destination.path) { continue }
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let image = downsampledJPEG(data: data) else { continue }
            try? image.write(to: destination, options: .atomic)
        }
        return snapshot
    }

    private static func downsampledJPEG(data: Data) -> Data? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 768
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.85)
    }

    static func load() -> AidokuWidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AidokuWidgetSnapshot.self, from: data)
    }
}

actor AidokuWidgetSnapshotRefreshCoordinator {
    static let shared = AidokuWidgetSnapshotRefreshCoordinator()
    private var pendingTask: Task<Void, Never>?

    func schedule() {
        pendingTask?.cancel()
        pendingTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await AidokuWidgetSnapshotStore.update()
        }
    }
}
