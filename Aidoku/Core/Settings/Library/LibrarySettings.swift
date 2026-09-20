//
//  LibrarySettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

import Foundation
import AidokuRunner

enum ChapterListOrder: String, CaseIterable {
    case automatic
    case descending
    case ascending

    var localizedTitle: String {
        switch self {
            case .automatic: NSLocalizedString("AUTOMATIC")
            case .descending: NSLocalizedString("DESCENDING")
            case .ascending: NSLocalizedString("ASCENDING")
        }
    }

    @MainActor
    func orderedChapters(
        _ chapters: [AidokuRunner.Chapter],
        for manga: AidokuRunner.Manga
    ) -> [AidokuRunner.Chapter] {
        let resolvedOrder = switch self {
            case .automatic:
                Self.effectiveReadingMode(for: manga) == .rtl ? Self.descending : Self.ascending
            case .descending, .ascending:
                self
        }

        // Sources provide chapters in descending source order. Reversing preserves the
        // source's own ordering while presenting the lowest source order first.
        return resolvedOrder == .ascending ? Array(chapters.reversed()) : chapters
    }

    @MainActor
    private static func effectiveReadingMode(for manga: AidokuRunner.Manga) -> ReadingMode {
        let perTitleMode = UserDefaults.standard.string(forKey: "Reader.readingMode.\(manga.identifier)")
        let selectedMode = perTitleMode == "default"
            ? UserDefaults.standard.string(forKey: "Reader.readingMode")
            : perTitleMode

        if let selectedMode, let mode = ReadingMode(selectedMode) {
            return mode
        }

        let viewerMode: ReadingMode? = switch manga.viewer {
            case .rightToLeft: .rtl
            case .leftToRight: .ltr
            case .vertical: .vertical
            case .webtoon: .webtoon
            case .unknown: nil
        }
        if let viewerMode {
            return viewerMode
        }

        if CoreDataManager.shared.hasManga(mangaId: manga.identifier),
           let mode = ReadingMode(rawValue: CoreDataManager.shared.getMangaSourceReadingMode(mangaId: manga.identifier))
        {
            return mode
        }

        return .rtl
    }
}

struct LibrarySettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            sortOption,
            sortAscending,
            listView,
            lastUpdated,
            opensReaderView,
            resumeLastOpenedChapter,
            continueReadingOnReselect,
            contextMenuPagePreviews,
            showChapterPageCounts,
            chapterListOrder,
            threeStateFilterMethods,
            visibleFilterMethods,
            unreadChapterBadges,
            downloadedChapterBadges,
            pinTitles,
            pinTitlesIgnoreFilters,
            pinTitlesIgnoredFilters,
            continueReadingIncludeNonLibraryTitles,
            continueReadingHideCaughtUpTitles,
            continueReadingIgnoreFilters,
            continueReadingIgnoredFilters,
            lockLibrary,
            currentCategory,
            defaultCategory,
            lockedCategories,
            showUncategorizedCategory,
            updateInterval,
            skipTitles,
            excludedUpdateCategories,
            backgroundRefresh,
            updateOnlyOnWifi,
            refreshMetadata,
            notifyNewChapters,
            disableSearchHistory,
            filtersData,
            favoritesSortOption,
            favoritesSortAscending,
            favoritesCurrentCategory,
            favoritesFiltersData,
            genreFilterConfigurationData
        ]
    }

    let sortOption = SettingsKey<Int>("Library.sortOption", default: LibraryViewModel.SortMethod.lastOpened.rawValue)
    let sortAscending = SettingsKey<Bool>("Library.sortAscending", default: false)
    let listView = SettingsKey<Bool>("Library.listView", default: false)

    let lastUpdated = SettingsKey<Date>("Library.lastUpdated", default: Date.distantPast)
    let opensReaderView = SettingsKey<Bool>("Library.opensReaderView", default: false)
    let resumeLastOpenedChapter = SettingsKey<Bool>("Library.resumeLastOpenedChapter", default: false)
    let continueReadingOnReselect = SettingsKey<Bool>("Library.continueReadingOnReselect", default: true)
    let contextMenuPagePreviews = SettingsKey<Bool>("Library.contextMenuPagePreviews", default: true)
    // Keep the existing key so moving the setting does not reset the user's choice.
    let showChapterPageCounts = SettingsKey<Bool>("Reader.showChapterPageCounts", default: false)
    let chapterListOrder = SettingsKey<String>("Library.chapterListOrder", default: ChapterListOrder.automatic.rawValue)
    let threeStateFilterMethods = SettingsKey<[String]>(
        "Library.threeStateFilterMethods",
        default: []
    )
    let visibleFilterMethods = SettingsKey<[String]>(
        "Library.visibleFilterMethods",
        default: LibraryFilter.FilterMethod.menuFilterMethods.map { String($0.rawValue) }
    )
    let unreadChapterBadges = SettingsKey<Bool>("Library.unreadChapterBadges", default: true)
    let downloadedChapterBadges = SettingsKey<Bool>("Library.downloadedChapterBadges", default: true)
    let pinTitles = SettingsKey<String>("Library.pinTitles", default: LibraryViewModel.PinType.none.rawValue)
    let pinTitlesIgnoreFilters = SettingsKey<Bool>("Library.pinTitlesIgnoreFilters", default: false)
    let pinTitlesIgnoredFilters = SettingsKey<[String]>(
        "Library.pinTitlesIgnoredFilters",
        default: LibraryFilter.FilterMethod.pinTitlesIgnoreFilterMethods.map(\.pinTitlesIgnoreFilterIdentifier)
    )
    let continueReadingIncludeNonLibraryTitles = SettingsKey<Bool>(
        "Library.continueReadingIncludeNonLibraryTitles",
        default: true
    )
    let continueReadingHideCaughtUpTitles = SettingsKey<Bool>(
        "Library.hideCaughtUpPinnedTitles",
        default: false
    )
    let continueReadingIgnoreFilters = SettingsKey<Bool>(
        "Library.continueReadingIgnoreFilters",
        default: false
    )
    let continueReadingIgnoredFilters = SettingsKey<[String]>(
        "Library.continueReadingIgnoredFilters",
        default: LibraryFilter.FilterMethod.pinTitlesIgnoreFilterMethods.map(\.pinTitlesIgnoreFilterIdentifier)
    )
    let lockLibrary = SettingsKey<Bool>("Library.lockLibrary", default: false)

    let currentCategory = SettingsKey<String?>("Library.currentCategory")
    let defaultCategory = SettingsKey<String?>("Library.defaultCategory")
    let lockedCategories = SettingsKey<[String]>("Library.lockedCategories", default: [])
    let showUncategorizedCategory = SettingsKey<Bool>("Library.showUncategorizedCategory", default: false)

    let updateInterval = SettingsKey<String>("Library.updateInterval", default: "daily")
    let skipTitles = SettingsKey<[String]>("Library.skipTitles", default: ["hasUnread", "completed", "notStarted"])
    let excludedUpdateCategories = SettingsKey<[String]>("Library.excludedUpdateCategories", default: [])
    let backgroundRefresh = SettingsKey<Bool>("Library.backgroundRefresh", default: true)
    let updateOnlyOnWifi = SettingsKey<Bool>("Library.updateOnlyOnWifi", default: true)
    let refreshMetadata = SettingsKey<Bool>("Library.refreshMetadata", default: false)
    let notifyNewChapters = SettingsKey<Bool>("Library.notifyNewChapters", default: false)
    let disableSearchHistory = SettingsKey<Bool>("Library.disableSearchHistory", default: false)

    let filtersData = SettingsKey<Data?>("Library.filters")
    // Favorites is a separate Library surface, so its presentation choices must
    // not overwrite the Library's saved sorting and filters.
    let favoritesSortOption = SettingsKey<Int>("Favorites.sortOption", default: LibraryViewModel.SortMethod.alphabetical.rawValue)
    let favoritesSortAscending = SettingsKey<Bool>("Favorites.sortAscending", default: false)
    let favoritesCurrentCategory = SettingsKey<String?>("Favorites.currentCategory")
    let favoritesFiltersData = SettingsKey<Data?>("Favorites.filters")
    let genreFilterConfigurationData = SettingsKey<Data?>("Library.genreFilterConfiguration")
}
