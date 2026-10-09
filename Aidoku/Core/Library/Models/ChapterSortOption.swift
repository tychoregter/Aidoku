//
//  ChapterSortOption.swift
//  Aidoku
//
//  Created by Skitty on 2/14/24.
//

import Foundation
import AidokuRunner

enum ChapterSortOption: Int, CaseIterable {
    // Zero has always meant the title follows the Library setting.
    case `default` = 0
    case chapter
    case uploadDate
    case sourceOrder
    case automatic

    static var allCases: [Self] { [.automatic, .sourceOrder, .chapter, .uploadDate] }

    init(flags: Int) {
        let option = (flags & ChapterFlagMask.sortMethod) >> 1
        self = ChapterSortOption(rawValue: option) ?? .default
    }

    var stringValue: String {
        switch self {
            case .default, .automatic: NSLocalizedString("AUTOMATIC")
            case .sourceOrder: NSLocalizedString("SOURCE_ORDER")
            case .chapter: NSLocalizedString("BOOK_ORDER", value: "Book Order", comment: "Sort chapters by their book number")
            case .uploadDate: NSLocalizedString("UPLOAD_DATE")
        }
    }
}

struct ChapterListPreferences: Codable {
    var flags: Int
    var language: String?
    var scanlators: [String]

    @MainActor
    static func load(for mangaId: MangaIdentifier) -> Self {
        if let data = UserDefaults.standard.data(forKey: key(for: mangaId)),
           let preferences = try? JSONDecoder().decode(Self.self, from: data) {
            return preferences
        }
        let saved = CoreDataManager.shared.getMangaChapterFilters(
            mangaId: mangaId, context: CoreDataManager.shared.context
        )
        return Self(flags: saved.flags, language: saved.language, scanlators: saved.scanlators ?? [])
    }

    func save(for mangaId: MangaIdentifier) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(for: mangaId))
        NotificationCenter.default.post(name: .filteredChapters, object: mangaId)
    }

    private static func key(for mangaId: MangaIdentifier) -> String {
        "Manga.chapterListPreferences.\(mangaId)"
    }
}

/// A per-series display name for numbered books. Keep source titles untouched so
/// refreshes, chapter matching, and missing-book detection use original metadata.
enum ChapterNaming {
    static let didChange = Notification.Name("ChapterNaming.didChange")

    static func prefix(for mangaId: MangaIdentifier) -> String? {
        guard AppSettings.general.bookRenaming.get() else { return nil }
        return storedPrefix(for: mangaId)
    }

    static func storedPrefix(for mangaId: MangaIdentifier) -> String? {
        UserDefaults.standard.string(forKey: key(for: mangaId))
    }

    static func setPrefix(_ value: String?, for mangaId: MangaIdentifier) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed?.isEmpty == false ? trimmed : nil
        UserDefaults.standard.set(prefix, forKey: key(for: mangaId))
        NotificationCenter.default.post(name: didChange, object: mangaId)
    }

    static func title(
        for chapter: AidokuRunner.Chapter,
        in mangaId: MangaIdentifier,
        useFullBookLabel: Bool = false
    ) -> String {
        if let prefix = prefix(for: mangaId),
           let number = chapter.chapterNumber ?? chapter.volumeNumber,
           number.isFinite {
            return "\(prefix) \(String(format: "%g", Double(number)))"
        }
        return useFullBookLabel ? chapter.readerTransitionDisplayTitle : chapter.sourceDisplayTitle
    }

    private static func key(for mangaId: MangaIdentifier) -> String {
        "Manga.chapterNamePrefix.\(mangaId)"
    }
}

@MainActor
enum ChapterListPresentation {
    static func orderedChapters(
        _ chapters: [AidokuRunner.Chapter],
        for manga: AidokuRunner.Manga,
        option: ChapterSortOption,
        ascending: Bool
    ) -> [AidokuRunner.Chapter] {
        switch option {
            case .default:
                return ChapterListOrder.current.orderedChapters(chapters, for: manga)
            case .automatic:
                return ChapterListOrder.automatic.orderedChapters(chapters, for: manga)
            case .sourceOrder:
                return ascending ? Array(chapters.reversed()) : chapters
            case .chapter:
                return chapters.enumerated().sorted { lhs, rhs in
                    let left = lhs.element.chapterNumber ?? lhs.element.volumeNumber
                    let right = rhs.element.chapterNumber ?? rhs.element.volumeNumber
                    if let left, let right, left.isFinite, right.isFinite, left != right {
                        return ascending ? left < right : left > right
                    }
                    let titleOrder = lhs.element.sourceDisplayTitle.localizedStandardCompare(
                        rhs.element.sourceDisplayTitle
                    )
                    if titleOrder != .orderedSame {
                        return ascending ? titleOrder == .orderedAscending : titleOrder == .orderedDescending
                    }
                    return lhs.offset < rhs.offset
                }.map(\.element)
            case .uploadDate:
                return chapters.sorted {
                    let left = $0.dateUploaded ?? .distantPast
                    let right = $1.dateUploaded ?? .distantPast
                    return ascending ? left < right : left > right
                }
        }
    }

    static func filteredChapters(
        _ chapters: [AidokuRunner.Chapter],
        for manga: AidokuRunner.Manga,
        filters: [ChapterFilterOption],
        language: String?,
        scanlators: [String],
        readingHistory: [String: (page: Int, date: Int)]
    ) -> [AidokuRunner.Chapter] {
        chapters.filter { chapter in
            if let language, chapter.language != language { return false }
            if !scanlators.isEmpty {
                let chapterScanlators = (chapter.scanlators?.isEmpty == false ? chapter.scanlators : nil) ?? [""]
                if !chapterScanlators.contains(where: scanlators.contains) { return false }
            }
            for filter in filters {
                let matches: Bool
                switch filter.type {
                    case .downloaded:
                        matches = DownloadManager.shared.isChapterDownloaded(chapter: .init(
                            sourceKey: manga.sourceKey,
                            mangaKey: manga.key,
                            chapterKey: chapter.key
                        ))
                    case .unread:
                        matches = readingHistory[chapter.id]?.page != -1
                    case .locked:
                        matches = chapter.locked
                }
                if matches == filter.exclude { return false }
            }
            return true
        }
    }
}
