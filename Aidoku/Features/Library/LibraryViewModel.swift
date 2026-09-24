//
//  LibraryViewModel.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/25/22.
//

import AidokuRunner
import CoreData
import UIKit

@MainActor
class LibraryViewModel {
    enum Scope: Equatable {
        case library
        case favorites
        case stack(UUID)
    }
    private static let favoritesKey = "library.favoriteMangaIdentifiers"

    var manga: [MangaInfo] = []
    var pinnedManga: [MangaInfo] = []
    var continueReadingManga: [MangaInfo] = []
    /// Pinned titles that also match the active Library filters. This is used
    /// for the optional duplicate copies in the regular Library section.
    var libraryPinnedManga: [MangaInfo] = []
    var sourceKeys: [String] = []
    var collections: [String] = []
    private var unfilteredLibraryManga: [MangaIdentifier: MangaInfo] = [:]

    var isFavoritesScope: Bool { scope == .favorites }
    var stackID: UUID? {
        guard case let .stack(id) = scope else { return nil }
        return id
    }

    enum PinType: String, CaseIterable {
        case none
        case favorites
        case started
        case unread
        case completed
        case updatedChapters

        var title: String {
            switch self {
                case .none: NSLocalizedString("PIN_DISABLED")
                case .unread: NSLocalizedString("PIN_UNREAD")
                case .updatedChapters: NSLocalizedString("PIN_UPDATED_CHAPTERS")
                case .started: NSLocalizedString("PIN_STARTED")
                case .favorites: NSLocalizedString("PIN_FAVORITES")
                case .completed: NSLocalizedString(
                    "FILTER_ENDED",
                    value: "Ended",
                    comment: "Pin Titles option for series that have ended"
                )
            }
        }

        var needsUpdateOnContentOpen: Bool {
            switch self {
                case .none: false
                case .unread: false
                case .updatedChapters: true
                case .started: true
                case .favorites: false
                case .completed: false
            }
        }
    }

    enum SortMethod: Int, CaseIterable {
        case alphabetical = 0
        case lastRead
        case lastOpened
        case lastUpdated
        case dateAdded
        case lastChapter
        case unreadChapters
        case totalChapters

        var title: String {
            switch self {
                case .alphabetical: NSLocalizedString("SORT_TITLE")
                case .lastRead: NSLocalizedString("SORT_LAST_READ")
                case .lastOpened: NSLocalizedString("SORT_LAST_OPENED")
                case .lastUpdated: NSLocalizedString("SORT_LAST_UPDATED")
                case .dateAdded: NSLocalizedString("SORT_DATE_ADDED")
                case .lastChapter: NSLocalizedString("SORT_LATEST_CHAPTER")
                case .unreadChapters: NSLocalizedString("SORT_UNREAD_CHAPTERS")
                case .totalChapters: NSLocalizedString("SORT_TOTAL_CHAPTERS")
            }
        }

        var descendingTitle: String {
            switch self {
                case .alphabetical: NSLocalizedString("ASCENDING") // reverse default for alphabetical sort
                case .lastRead: NSLocalizedString("NEWEST_FIRST")
                case .lastOpened: NSLocalizedString("NEWEST_FIRST")
                case .lastUpdated: NSLocalizedString("NEWEST_FIRST")
                case .dateAdded: NSLocalizedString("NEWEST_FIRST")
                case .lastChapter: NSLocalizedString("NEWEST_FIRST")
                case .unreadChapters: NSLocalizedString("HIGHEST_FIRST")
                case .totalChapters: NSLocalizedString("HIGHEST_FIRST")
            }
        }

        var ascendingTitle: String {
            switch self {
                case .alphabetical: NSLocalizedString("DESCENDING")
                case .lastRead: NSLocalizedString("OLDEST_FIRST")
                case .lastOpened: NSLocalizedString("OLDEST_FIRST")
                case .lastUpdated: NSLocalizedString("OLDEST_FIRST")
                case .dateAdded: NSLocalizedString("OLDEST_FIRST")
                case .lastChapter: NSLocalizedString("OLDEST_FIRST")
                case .unreadChapters: NSLocalizedString("LOWEST_FIRST")
                case .totalChapters: NSLocalizedString("LOWEST_FIRST")
            }
        }

        func directionTitle(ascending: Bool) -> String {
            ascending ? ascendingTitle : descendingTitle
        }

        var sortStringValue: String {
            switch self {
                case .alphabetical: "manga.title"
                case .lastRead: "lastRead"
                case .lastOpened: "lastOpened"
                case .lastUpdated: "lastUpdated"
                case .dateAdded: "dateAdded"
                case .lastChapter: "lastChapter"
                case .unreadChapters: ""
                case .totalChapters: "manga.chapterCount"
            }
        }
    }

    struct BadgeType: OptionSet {
        let rawValue: Int

        static let unread = BadgeType(rawValue: 1 << 0)
        static let downloaded = BadgeType(rawValue: 1 << 1)
    }

    let scope: Scope
    var pinType: PinType
    var sortMethod: SortMethod
    var sortAscending: Bool
    lazy var badgeType: BadgeType = {
        var type: BadgeType = []
        if AppSettings.library.unreadChapterBadges.get() {
            type.insert(.unread)
        }
        if AppSettings.library.downloadedChapterBadges.get() {
            type.insert(.downloaded)
        }
        return type
    }()

    var filters: [LibraryFilter] {
        didSet {
            saveFilters()
        }
    }
    private(set) var favoriteIds: Set<String>
    var activeFilters: [LibraryFilter] {
        if let currentCategory, let group = filterGroups.first(where: { $0.title == currentCategory }) {
            group.filters + self.filters
        } else {
            self.filters
        }
    }

    var categories: [String] = []
    var filterGroups: [FilterGroup] = []
    var availableGenres: [LibraryFilter.Genre] = []
    var currentCategory: String? {
        didSet {
            if scope == .favorites {
                AppSettings.library.favoritesCurrentCategory.set(currentCategory)
            } else {
                AppSettings.library.currentCategory.set(currentCategory)
            }
        }
    }
    var isInRealCategory: Bool {
        if let currentCategory, !currentCategory.isEmpty {
            categories.contains(currentCategory)
        } else {
            false
        }
    }
    var isInUncategorizedCategory: Bool {
        currentCategory?.isEmpty ?? false
    }
    private(set) var actuallyEmpty = true
    private let loadsDedicatedContinueReading: Bool
    private let usesContinueReadingSettings: Bool

    // Several independent notifications can request a library reload at the
    // same time. Since this type is main-actor isolated, each load can suspend
    // while Core Data works and otherwise allow another load to start. Keep a
    // single load in flight and fold requests received during it into one
    // follow-up pass instead of accumulating background contexts.
    private var isLoadingLibrary = false
    private var libraryReloadPending = false
    private var libraryLoadWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        loadsDedicatedContinueReading: Bool = true,
        usesContinueReadingSettings: Bool = false,
        scope: Scope = .library
    ) {
        self.scope = scope
        self.loadsDedicatedContinueReading = loadsDedicatedContinueReading
        self.usesContinueReadingSettings = usesContinueReadingSettings
        let savedPinType = PinType(rawValue: AppSettings.library.pinTitles.get()) ?? .none
        pinType = (scope != .library || (Self.isDedicatedContinueReadingEnabled && savedPinType == .started))
            ? .none
            : savedPinType
        sortMethod = SortMethod(rawValue: scope == .favorites
            ? AppSettings.library.favoritesSortOption.get()
            : AppSettings.library.sortOption.get()) ?? .lastOpened
        sortAscending = scope == .favorites
            ? AppSettings.library.favoritesSortAscending.get()
            : AppSettings.library.sortAscending.get()
        currentCategory = scope == .favorites
            ? AppSettings.library.favoritesCurrentCategory.get()
            : AppSettings.library.currentCategory.get()
        favoriteIds = Set(UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? [])
        let filtersData = scope == .favorites
            ? AppSettings.library.favoritesFiltersData.get()
            : AppSettings.library.filtersData.get()
        if let filtersData {
            let decodedFilters = (try? JSONDecoder().decode([LibraryFilter].self, from: filtersData)) ?? []
            var retainedGenre = false
            let filters = decodedFilters.filter { filter in
                guard filter.type == .genre else { return true }
                guard !filter.exclude, !retainedGenre else { return false }
                retainedGenre = true
                return true
            }
            self.filters = filters
            if filters != decodedFilters, let migratedFiltersData = try? JSONEncoder().encode(filters) {
                if scope == .favorites {
                    AppSettings.library.favoritesFiltersData.set(migratedFiltersData)
                } else {
                    AppSettings.library.filtersData.set(migratedFiltersData)
                }
            }
        } else {
            self.filters = []
        }
    }

    func isFavorite(_ mangaId: MangaIdentifier) -> Bool {
        favoriteIds.contains(mangaId.description)
    }

    func toggleFavorite(_ mangaId: MangaIdentifier) {
        if !favoriteIds.insert(mangaId.description).inserted {
            favoriteIds.remove(mangaId.description)
        }
        UserDefaults.standard.set(Array(favoriteIds), forKey: Self.favoritesKey)
        NotificationCenter.default.post(name: .favoriteChanged, object: mangaId)
    }

    func synchronizeSharedLibraryOptions() {
        guard scope == .library else { return }

        sortMethod = SortMethod(rawValue: AppSettings.library.sortOption.get()) ?? .lastOpened
        sortAscending = AppSettings.library.sortAscending.get()

        let decodedFilters = AppSettings.library.filtersData.get()
            .flatMap { try? JSONDecoder().decode([LibraryFilter].self, from: $0) } ?? []
        var retainedGenre = false
        filters = decodedFilters.filter { filter in
            guard filter.type == .genre else { return true }
            guard !filter.exclude, !retainedGenre else { return false }
            retainedGenre = true
            return true
        }
    }
}

extension LibraryViewModel {
    func isCategoryLocked() -> Bool {
        guard AppSettings.library.lockLibrary.get() else { return false }
        if let currentCategory, !currentCategory.isEmpty {
            let lockedCategories = AppSettings.library.lockedCategories.get()
            return lockedCategories.contains(currentCategory)
        }
        return true
    }

    func getPinType() -> PinType {
        let pinType = PinType(rawValue: AppSettings.library.pinTitles.get()) ?? .none
        if Self.isDedicatedContinueReadingEnabled, pinType == .started {
            AppSettings.library.pinTitles.set(PinType.none.rawValue)
            return .none
        }
        return pinType
    }

    static var isDedicatedContinueReadingEnabled: Bool {
        AppSettings.appearance.dedicatedContinueReadingSection.get()
    }

    func refreshCategories(skipDataLoad: Bool = false) async {
        (categories, filterGroups) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            (
                CoreDataManager.shared.getCategoryTitles(context: context),
                CoreDataManager.shared.getFilterGroups(context: context)
            )
        }
        if !skipDataLoad {
            let isInFilterGroup = filterGroups.contains(where: { $0.title == currentCategory })
            let showUncategorized = AppSettings.library.showUncategorizedCategory.get()
            if let currentCategory, (!categories.contains(currentCategory) && !isInFilterGroup) || (currentCategory.isEmpty && !showUncategorized) {
                self.currentCategory = nil
                await loadLibrary()
            } else if isInFilterGroup {
                // refresh filter group in case filters changed
                await loadLibrary()
            }
        }
    }

    func loadLibrary() async {
        if isLoadingLibrary {
            libraryReloadPending = true
            await withCheckedContinuation { continuation in
                libraryLoadWaiters.append(continuation)
            }
            return
        }

        isLoadingLibrary = true
        repeat {
            libraryReloadPending = false
            await performLibraryLoad()
        } while libraryReloadPending

        if loadsDedicatedContinueReading {
            await loadDedicatedContinueReading()
        }
        isLoadingLibrary = false

        let waiters = libraryLoadWaiters
        libraryLoadWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func loadDedicatedContinueReading() async {
        guard Self.isDedicatedContinueReadingEnabled else {
            continueReadingManga = []
            return
        }

        let readingViewModel = LibraryViewModel(
            loadsDedicatedContinueReading: false,
            usesContinueReadingSettings: true
        )
        readingViewModel.pinType = .started
        readingViewModel.sortMethod = sortMethod
        readingViewModel.sortAscending = sortAscending
        readingViewModel.categories = categories
        readingViewModel.filterGroups = filterGroups
        readingViewModel.currentCategory = currentCategory
        readingViewModel.filters = filters
        await readingViewModel.loadLibrary()

        continueReadingManga = readingViewModel.pinnedManga.map { manga in
            var manga = manga
            manga.displayVariant = "continue-reading"
            return manga
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func performLibraryLoad() async {
        // Favorites can be changed from the manga details screen while this view remains alive.
        favoriteIds = Set(UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? [])

        // handle filter groups
        let filters = self.activeFilters
        let currentCategory = (isInUncategorizedCategory || isInRealCategory) ? self.currentCategory : nil
        let pinTitlesIgnoreFilters = if usesContinueReadingSettings {
            AppSettings.library.continueReadingIgnoreFilters.get()
        } else {
            AppSettings.library.pinTitlesIgnoreFilters.get()
        }
        let hideCaughtUpTitles = usesContinueReadingSettings
            && AppSettings.library.continueReadingHideCaughtUpTitles.get()
        let includesNonLibraryContinueReadingTitles = usesContinueReadingSettings
            && AppSettings.library.continueReadingIncludeNonLibraryTitles.get()
        var nonLibraryHistoryDates: [MangaIdentifier: Date] = [:]
        if includesNonLibraryContinueReadingTitles,
           currentCategory == nil || currentCategory?.isEmpty == true {
            nonLibraryHistoryDates = await loadNonLibraryContinueReadingMetadata()
        }
        let ignoredFilterIdentifiers = if usesContinueReadingSettings {
            AppSettings.library.continueReadingIgnoredFilters.get()
        } else {
            AppSettings.library.pinTitlesIgnoredFilters.get()
        }
        let ignoredPinFilterMethods = Set(
            ignoredFilterIdentifiers.compactMap(
                LibraryFilter.FilterMethod.pinTitlesIgnoreFilterMethod(for:)
            )
        )

        let isFavoritesOnly = scope == .favorites
        let stackMembers: Set<MangaIdentifier>? = LibraryBundleFeature.isEnabled ? stackID.flatMap {
            LibraryStackStore.shared.stack(id: $0).map { Set($0.members) }
        } : nil
        let stackedMemberIDs = LibraryBundleFeature.isEnabled && scope == .library
            ? Set(LibraryStackStore.shared.stacks.flatMap(\.members))
            : Set<MangaIdentifier>()
        let (
            success,
            actuallyEmpty,
            pinnedManga,
            libraryPinnedManga,
            manga,
            ignoredFilterPinnedManga,
            sourceKeys,
            unappliedFilters,
            availableGenres,
            allLibraryManga
        ) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable [sortMethod, sortAscending, pinType, favoriteIds, pinTitlesIgnoreFilters, ignoredPinFilterMethods, nonLibraryHistoryDates, isFavoritesOnly, stackMembers, stackedMemberIDs] context in
            var pinnedManga: [MangaInfo] = []
            var libraryPinnedManga: [MangaInfo] = []
            var manga: [MangaInfo] = []
            var ignoredFilterPinnedManga: [MangaInfo] = []
            var sourceKeys: Set<String> = []
            var unappliedFilters: [LibraryFilter] = []
            var allLibraryManga: [MangaInfo] = []

            let request = LibraryMangaObject.fetchRequest()
            if let currentCategory {
                if currentCategory.isEmpty {
                    request.predicate = NSPredicate(format: "manga != nil AND categories.@count == 0")
                } else {
                    request.predicate = NSPredicate(format: "manga != nil AND ANY categories.title == %@", currentCategory)
                }
            } else {
                request.predicate = NSPredicate(format: "manga != nil")
            }
            if sortMethod != .unreadChapters {
                request.sortDescriptors = [
                    NSSortDescriptor(
                        key: sortMethod.sortStringValue,
                        ascending: sortMethod == .alphabetical ? !sortAscending : sortAscending
                    )
                ]
            }
            guard let libraryObjects = try? context.fetch(request) else {
                return (false, true, pinnedManga, libraryPinnedManga, manga, ignoredFilterPinnedManga, sourceKeys, unappliedFilters, [LibraryFilter.Genre](), allLibraryManga)
            }

            var stackLibraryObjects: [LibraryMangaObject] = []
            if !stackedMemberIDs.isEmpty {
                let stackRequest = LibraryMangaObject.fetchRequest()
                stackRequest.predicate = NSPredicate(format: "manga != nil")
                let objects = (try? context.fetch(stackRequest)) ?? []
                stackLibraryObjects = objects.filter { object in
                    object.manga.map { stackedMemberIDs.contains($0.identifier) } ?? false
                }
            }

            let actuallyEmpty = libraryObjects.isEmpty
            let nonLibraryManga: [(manga: MangaObject, lastRead: Date)] = nonLibraryHistoryDates.compactMap {
                identifier, lastRead in
                guard
                    let manga = CoreDataManager.shared.getManga(mangaId: identifier, context: context),
                    manga.libraryObject == nil
                else { return nil }
                return (manga, lastRead)
            }
            let genreConfiguration = LibraryGenreFilterSettings.load()
            let availableGenres = LibraryGenreFilterSettings.availableFilterGenres(
                from: (libraryObjects.compactMap(\.manga) + nonLibraryManga.map(\.manga)).reduce(into: [String]()) {
                    values, manga in
                    if manga.sourceId.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
                        values.append(contentsOf: KomgaGenreStore.genres(sourceKey: manga.sourceId, mangaKey: manga.id))
                    } else {
                        values.append(contentsOf: manga.tags ?? [])
                    }
                },
                configuration: genreConfiguration
            )

            var ids = Set<MangaIdentifier>()

            let infoLibraryObjects = (libraryObjects + stackLibraryObjects).reduce(into: [LibraryMangaObject]()) {
                result, object in
                guard let identifier = object.manga?.identifier,
                      !result.contains(where: { $0.manga?.identifier == identifier }) else { return }
                result.append(object)
            }
            allLibraryManga = infoLibraryObjects.enumerated().compactMap { index, libraryObject in
                guard let mangaObject = libraryObject.manga else { return nil }
                var info = MangaInfo(
                    id: mangaObject.identifier,
                    coverUrl: mangaObject.cover.flatMap { URL(string: $0) },
                    title: mangaObject.title,
                    author: mangaObject.author,
                    url: mangaObject.url.flatMap { URL(string: $0) }
                )
                info.isNSFW = mangaObject.nsfw == MangaContentRating.nsfw.rawValue
                info.lastRead = libraryObject.lastRead
                info.libraryLastOpened = libraryObject.lastOpened
                info.libraryLastUpdated = libraryObject.lastUpdated
                info.libraryDateAdded = libraryObject.dateAdded
                info.libraryLastChapter = libraryObject.lastChapter
                info.totalChapters = mangaObject.chapters?.count ?? 0
                info.librarySortIndex = index
                return info
            }

            main: for (librarySortIndex, libraryObject) in libraryObjects.enumerated() {
                guard
                    let mangaObject = libraryObject.manga,
                    // ensure the manga hasn't already been accounted for
                    ids.insert(mangaObject.identifier).inserted
                else {
                    continue
                }

                guard stackMembers?.contains(mangaObject.identifier) ?? true else { continue }

                guard !isFavoritesOnly || favoriteIds.contains(mangaObject.identifier.description) else {
                    continue
                }

                let categories = (libraryObject.categories?.allObjects as? [CategoryObject])?.map { $0.title } ?? []

                var info = MangaInfo(
                    id: mangaObject.identifier,
                    coverUrl: mangaObject.cover.flatMap { URL(string: $0) },
                    title: mangaObject.title,
                    author: mangaObject.author,
                    url: mangaObject.url.flatMap { URL(string: $0) }
                )
                info.isNSFW = mangaObject.nsfw == MangaContentRating.nsfw.rawValue
                info.lastRead = libraryObject.lastRead
                info.libraryLastOpened = libraryObject.lastOpened
                info.libraryLastUpdated = libraryObject.lastUpdated
                info.libraryDateAdded = libraryObject.dateAdded
                info.libraryLastChapter = libraryObject.lastChapter
                info.totalChapters = mangaObject.chapters?.count ?? 0
                info.librarySortIndex = librarySortIndex

                if pinType == .started {
                    let chapters = ((mangaObject.chapters?.allObjects as? [ChapterObject]) ?? [])
                        .filter { !$0.locked }
                        .sorted { $0.sourceOrder < $1.sourceOrder }
                    let newestCompletedIndex = chapters.firstIndex { $0.history?.completed == true }
                    let wasCaughtUpBeforeUpdate = newestCompletedIndex.map { index in
                        chapters[index...].allSatisfy { $0.history?.completed == true }
                    } ?? false
                    if wasCaughtUpBeforeUpdate {
                        if let lastRead = libraryObject.lastRead {
                            info.pinSortDate = libraryObject.lastUpdatedChapters > lastRead
                                ? libraryObject.lastUpdatedChapters
                                : lastRead
                        } else {
                            info.pinSortDate = libraryObject.lastUpdatedChapters
                        }
                    } else {
                        info.pinSortDate = libraryObject.lastRead
                    }
                } else if pinType == .updatedChapters {
                    info.pinSortDate = libraryObject.lastUpdatedChapters
                }

                sourceKeys.insert(mangaObject.sourceId)

                let isPinnedIgnoringFilters = switch pinType {
                    case .none: false
                    case .unread: true
                    case .updatedChapters: libraryObject.lastUpdatedChapters > libraryObject.lastOpened
                    case .started: CoreDataManager.shared.hasHistory(mangaId: info.id, context: context)
                    case .favorites: favoriteIds.contains(info.id.description)
                    case .completed: mangaObject.status == AidokuRunner.PublishingStatus.completed.rawValue
                }
                func appendIgnoringFiltersIfNeeded(for method: LibraryFilter.FilterMethod) {
                    guard
                        pinTitlesIgnoreFilters,
                        ignoredPinFilterMethods.contains(method),
                        isPinnedIgnoringFilters
                    else { return }
                    if pinType == .unread {
                        ignoredFilterPinnedManga.append(info)
                    } else {
                        pinnedManga.append(info)
                    }
                }

                // process filters
                var filteredSourceKeys: Set<String> = []
                var filteredContentRatings: Set<Int16> = []
                var filteredCategories: Set<String> = []
                var filteredGenres: Set<LibraryFilter.Genre> = []
                for filter in filters {
                    let condition: Bool
                    switch filter.type {
                        case .downloaded:
                            unappliedFilters.append(filter)
                            continue
                        case .tracking:
                            condition = CoreDataManager.shared.hasTrack(
                                mangaId: info.id,
                                context: context
                            )
                        case .hasUnread:
                            unappliedFilters.append(filter)
                            continue
                        case .caughtUp:
                            unappliedFilters.append(filter)
                            continue
                        case .started:
                            condition = CoreDataManager.shared.hasHistory(
                                mangaId: info.id,
                                context: context
                            )
                        case .completed:
                            condition = mangaObject.status == AidokuRunner.PublishingStatus.completed.rawValue
                        case .source:
                            guard let sourceId = filter.value else { continue }
                            if filter.exclude {
                                condition = info.id.sourceKey == sourceId
                            } else {
                                // handle included source filters as OR
                                filteredSourceKeys.insert(sourceId)
                                continue
                            }
                        case .contentRating:
                            guard let contentRating = filter.value.flatMap(MangaContentRating.init) else { continue }
                            if filter.exclude {
                                condition = mangaObject.nsfw == contentRating.rawValue
                            } else {
                                // handle included content rating filters as OR
                                filteredContentRatings.insert(Int16(contentRating.rawValue))
                                continue
                            }
                        case .category:
                            guard let category = filter.value else { continue }
                            if filter.exclude {
                                condition = categories.contains(category)
                            } else {
                                // handle included category filters as OR
                                filteredCategories.insert(category)
                                continue
                            }
                        case .favorite:
                            condition = favoriteIds.contains(info.id.description)
                        case .collection:
                            guard let collection = filter.value else { continue }
                            let memberships = (UserDefaults.standard.dictionary(forKey: "\(info.id.sourceKey).collectionMembership") as? [String: [String]] ?? [:])[info.id.mangaKey] ?? []
                            condition = memberships.contains(collection)
                        case .genre:
                            guard let value = filter.value,
                                  let genre = LibraryGenreFilterSettings.matchingGenre(
                                    for: value,
                                    in: availableGenres,
                                    configuration: genreConfiguration
                                  )
                            else { continue }
                            let mangaGenres = if mangaObject.sourceId.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
                                KomgaGenreStore.genres(sourceKey: mangaObject.sourceId, mangaKey: mangaObject.id)
                            } else {
                                mangaObject.tags ?? []
                            }
                            if filter.exclude {
                                condition = mangaGenres.contains(where: genre.matches)
                            } else {
                                filteredGenres.insert(genre)
                                continue
                            }

                    }
                    let shouldSkip = filter.exclude ? condition : !condition
                    if shouldSkip {
                        appendIgnoringFiltersIfNeeded(for: filter.type)
                        continue main
                    }
                }
                if !filteredSourceKeys.isEmpty && !filteredSourceKeys.contains(info.id.sourceKey) {
                    appendIgnoringFiltersIfNeeded(for: .source)
                    continue main
                }
                if !filteredContentRatings.isEmpty && !filteredContentRatings.contains(mangaObject.nsfw) {
                    appendIgnoringFiltersIfNeeded(for: .contentRating)
                    continue main
                }
                if !filteredCategories.isEmpty && !filteredCategories.contains(where: { categories.contains($0) }) {
                    appendIgnoringFiltersIfNeeded(for: .category)
                    continue main
                }
                if !filteredGenres.isEmpty && !filteredGenres.contains(where: { genre in
                    let mangaGenres = if mangaObject.sourceId.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
                        KomgaGenreStore.genres(sourceKey: mangaObject.sourceId, mangaKey: mangaObject.id)
                    } else {
                        mangaObject.tags ?? []
                    }
                    return mangaGenres.contains(where: genre.matches)
                }) {
                    appendIgnoringFiltersIfNeeded(for: .genre)
                    continue main
                }

                switch pinType {
                    case .none:
                        manga.append(info)
                    case .unread:
                        // don't have unread info to sort yet
                        manga.append(info)
                    case .updatedChapters:
                        if libraryObject.lastUpdatedChapters > libraryObject.lastOpened {
                            pinnedManga.append(info)
                            libraryPinnedManga.append(info)
                        } else {
                            manga.append(info)
                        }
                    case .started:
                        if CoreDataManager.shared.hasHistory(mangaId: info.id, context: context) {
                            pinnedManga.append(info)
                            libraryPinnedManga.append(info)
                        } else {
                            manga.append(info)
                        }
                    case .favorites:
                        if favoriteIds.contains(info.id.description) {
                            pinnedManga.append(info)
                            libraryPinnedManga.append(info)
                        } else {
                            manga.append(info)
                        }
                    case .completed:
                        if mangaObject.status == AidokuRunner.PublishingStatus.completed.rawValue {
                            pinnedManga.append(info)
                            libraryPinnedManga.append(info)
                        } else {
                            manga.append(info)
                    }
                }
            }

            nonLibrary: for (mangaObject, lastRead) in nonLibraryManga {
                guard ids.insert(mangaObject.identifier).inserted else { continue }

                var info = MangaInfo(
                    id: mangaObject.identifier,
                    coverUrl: mangaObject.cover.flatMap { URL(string: $0) },
                    title: mangaObject.title,
                    author: mangaObject.author,
                    url: mangaObject.url.flatMap { URL(string: $0) }
                )
                info.isNSFW = mangaObject.nsfw == MangaContentRating.nsfw.rawValue
                info.lastRead = lastRead
                info.pinSortDate = lastRead
                info.librarySortIndex = libraryObjects.count + pinnedManga.count

                sourceKeys.insert(mangaObject.sourceId)

                func appendIgnoringFiltersIfNeeded(for method: LibraryFilter.FilterMethod) {
                    guard pinTitlesIgnoreFilters, ignoredPinFilterMethods.contains(method) else { return }
                    pinnedManga.append(info)
                }

                var filteredSourceKeys: Set<String> = []
                var filteredContentRatings: Set<Int16> = []
                var filteredCategories: Set<String> = []
                var filteredGenres: Set<LibraryFilter.Genre> = []
                for filter in filters {
                    let condition: Bool
                    switch filter.type {
                        case .downloaded, .hasUnread, .caughtUp:
                            unappliedFilters.append(filter)
                            continue
                        case .tracking:
                            condition = CoreDataManager.shared.hasTrack(
                                mangaId: info.id,
                                context: context
                            )
                        case .started:
                            condition = true
                        case .completed:
                            condition = mangaObject.status == AidokuRunner.PublishingStatus.completed.rawValue
                        case .source:
                            guard let sourceId = filter.value else { continue }
                            if filter.exclude {
                                condition = info.id.sourceKey == sourceId
                            } else {
                                filteredSourceKeys.insert(sourceId)
                                continue
                            }
                        case .contentRating:
                            guard let contentRating = filter.value.flatMap(MangaContentRating.init) else { continue }
                            if filter.exclude {
                                condition = mangaObject.nsfw == contentRating.rawValue
                            } else {
                                filteredContentRatings.insert(Int16(contentRating.rawValue))
                                continue
                            }
                        case .category:
                            guard let category = filter.value else { continue }
                            if filter.exclude {
                                condition = false
                            } else {
                                filteredCategories.insert(category)
                                continue
                            }
                        case .favorite:
                            condition = favoriteIds.contains(info.id.description)
                        case .collection:
                            guard let collection = filter.value else { continue }
                            let memberships = (
                                UserDefaults.standard.dictionary(
                                    forKey: "\(info.id.sourceKey).collectionMembership"
                                ) as? [String: [String]] ?? [:]
                            )[info.id.mangaKey] ?? []
                            condition = memberships.contains(collection)
                        case .genre:
                            guard let value = filter.value,
                                  let genre = LibraryGenreFilterSettings.matchingGenre(
                                    for: value,
                                    in: availableGenres,
                                    configuration: genreConfiguration
                                  )
                            else { continue }
                            let mangaGenres = if mangaObject.sourceId.hasPrefix(
                                KomgaSourceRunner.sourceKeyPrefix
                            ) {
                                KomgaGenreStore.genres(
                                    sourceKey: mangaObject.sourceId,
                                    mangaKey: mangaObject.id
                                )
                            } else {
                                mangaObject.tags ?? []
                            }
                            if filter.exclude {
                                condition = mangaGenres.contains(where: genre.matches)
                            } else {
                                filteredGenres.insert(genre)
                                continue
                            }
                    }
                    let shouldSkip = filter.exclude ? condition : !condition
                    if shouldSkip {
                        appendIgnoringFiltersIfNeeded(for: filter.type)
                        continue nonLibrary
                    }
                }
                if !filteredSourceKeys.isEmpty && !filteredSourceKeys.contains(info.id.sourceKey) {
                    appendIgnoringFiltersIfNeeded(for: .source)
                    continue nonLibrary
                }
                if !filteredContentRatings.isEmpty && !filteredContentRatings.contains(mangaObject.nsfw) {
                    appendIgnoringFiltersIfNeeded(for: .contentRating)
                    continue nonLibrary
                }
                if !filteredCategories.isEmpty {
                    appendIgnoringFiltersIfNeeded(for: .category)
                    continue nonLibrary
                }
                if !filteredGenres.isEmpty && !filteredGenres.contains(where: { genre in
                    let mangaGenres = if mangaObject.sourceId.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
                        KomgaGenreStore.genres(sourceKey: mangaObject.sourceId, mangaKey: mangaObject.id)
                    } else {
                        mangaObject.tags ?? []
                    }
                    return mangaGenres.contains(where: genre.matches)
                }) {
                    appendIgnoringFiltersIfNeeded(for: .genre)
                    continue nonLibrary
                }

                pinnedManga.append(info)
            }

            if pinType == .started || pinType == .updatedChapters {
                pinnedManga.sort {
                    if let lhs = $0.pinSortDate, let rhs = $1.pinSortDate {
                        return lhs > rhs
                    }
                    return $0.pinSortDate != nil
                }
            }

            return (true, actuallyEmpty, pinnedManga, libraryPinnedManga, manga, ignoredFilterPinnedManga, sourceKeys, unappliedFilters, availableGenres, allLibraryManga)
        }

        guard success else { return }

        if LibraryBundleFeature.isEnabled, scope == .library {
            LibraryStackStore.shared.prune(validManga: Set(allLibraryManga.map(\.id)))
            unfilteredLibraryManga = Dictionary(
                allLibraryManga.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        self.pinnedManga = pinnedManga
        self.libraryPinnedManga = libraryPinnedManga
        self.manga = manga
        if pinType == .unread {
            self.pinnedManga.append(contentsOf: ignoredFilterPinnedManga)
        }
        self.sourceKeys = sourceKeys.sorted()
        self.availableGenres = availableGenres
        self.collections = sourceKeys.flatMap { sourceKey in
            (UserDefaults.standard.dictionary(forKey: "\(sourceKey).collectionMembership") as? [String: [String]] ?? [:]).values.flatMap { $0 }
        }.sorted().reduce(into: []) { result, value in
            if result.last != value { result.append(value) }
        }
        self.actuallyEmpty = if stackID != nil {
            stackMembers?.isEmpty ?? true
        } else if scope == .library {
            actuallyEmpty
        } else {
            manga.isEmpty
        }

        await fetchUnreads(skipSortCheck: true)
        await fetchDownloadCounts()

        // Keep the duplicate Library-section copies in sync with the resolved
        // unread/download counts used by late-applied filters such as Caught Up.
        // The identifier set still ensures titles bypassing an earlier filter
        // remain exclusive to the Pinned section.
        if pinType != .unread {
            let libraryPinnedIDs = Set(self.libraryPinnedManga.map(\.id))
            self.libraryPinnedManga = self.pinnedManga.filter {
                libraryPinnedIDs.contains($0.id)
            }
        }

        if hideCaughtUpTitles {
            self.pinnedManga.removeAll { $0.unread == 0 }
        }

        if !unappliedFilters.isEmpty {
            let filter: (MangaInfo, Bool) -> Bool = { info, ignoresSelectedFilters in
                for filter in unappliedFilters {
                    if ignoresSelectedFilters && ignoredPinFilterMethods.contains(filter.type) {
                        continue
                    }
                    let condition: Bool
                    switch filter.type {
                        case .downloaded: condition = info.downloads > 0
                        case .hasUnread: condition = info.unread > 0
                        case .caughtUp: condition = info.unread == 0
                        default: continue
                    }
                    let shouldSkip = filter.exclude ? condition : !condition
                    guard !shouldSkip else { return false }
                }
                return true
            }
            self.pinnedManga = self.pinnedManga.filter { filter($0, pinTitlesIgnoreFilters) }
            self.libraryPinnedManga = self.libraryPinnedManga.filter { filter($0, false) }
            self.manga = self.manga.filter { filter($0, false) }
        }

        if pinType == .unread {
            let libraryPinnedIDs = Set(self.manga.filter { $0.unread > 0 }.map(\.id))
            let currentManga = self.manga + self.pinnedManga
            var pinnedManga: [MangaInfo] = []
            var manga: [MangaInfo] = []
            let ignoredFilterPinnedIds = Set(ignoredFilterPinnedManga.map(\.id))
            for item in currentManga {
                if item.unread > 0 {
                    pinnedManga.append(item)
                } else if !ignoredFilterPinnedIds.contains(item.id) {
                    manga.append(item)
                }
            }
            self.pinnedManga = pinnedManga
            self.libraryPinnedManga = self.pinnedManga.filter { libraryPinnedIDs.contains($0.id) }
            self.manga = manga
        }

        if sortMethod == .unreadChapters {
            await sortLibrary()
        }

    }

    func stackLibraryItems(_ items: [MangaInfo]) -> [MangaInfo] {
        guard LibraryBundleFeature.isEnabled, scope == .library else { return items }
        let stacks = LibraryStackStore.shared.stacks
        guard !stacks.isEmpty else { return items }

        let stackByMember = stacks.reduce(into: [MangaIdentifier: LibraryStack]()) { result, stack in
            for member in stack.members { result[member] = stack }
        }
        let visibleIDs = Set(items.map(\.id))
        let pinnedIDs = Set(pinnedManga.map(\.id))
        var result = items.filter { stackByMember[$0.id] == nil }
        let currentInfo = Dictionary(
            (manga + pinnedManga + libraryPinnedManga + items).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for stack in stacks {
            let members = stack.members.compactMap { currentInfo[$0] ?? unfilteredLibraryManga[$0] }
            guard !members.isEmpty else { continue }
            let hasVisibleMember = stack.members.contains(where: visibleIDs.contains)
            let canRecoverAggregateFilterMatch = !activeFilters.isEmpty
                && stack.members.contains { !pinnedIDs.contains($0) }
                && stackMatchesActiveFilters(stack, infoByID: currentInfo)
            guard hasVisibleMember || canRecoverAggregateFilterMatch else { continue }
            let coverID = stack.coverManga ?? stack.members.first
            let storedCover = coverID.flatMap {
                CoreDataManager.shared.getManga(
                    mangaId: $0,
                    context: CoreDataManager.shared.container.viewContext
                )
            }
            let coverMember = coverID.flatMap { currentInfo[$0] ?? unfilteredLibraryManga[$0] }
            let customCover = LibraryStackStore.shared.customCoverURL(for: stack)
            result.append(.libraryStack(
                id: stack.id,
                title: stack.name,
                coverURL: customCover
                    ?? storedCover?.cover.flatMap { URL(string: $0) }
                    ?? coverMember?.coverUrl
                    ?? members[0].coverUrl,
                coverIdentifier: customCover == nil ? coverID : nil,
                itemCount: stack.members.count,
                dateCreated: stack.dateCreated,
                unread: members.reduce(0) { $0 + $1.unread },
                downloads: members.reduce(0) { $0 + $1.downloads },
                lastRead: members.compactMap(\.lastRead).max(),
                lastOpened: members.compactMap(\.libraryLastOpened).max(),
                lastUpdated: members.compactMap(\.libraryLastUpdated).max(),
                lastChapter: members.compactMap(\.libraryLastChapter).max(),
                totalChapters: members.reduce(0) { $0 + $1.totalChapters },
                librarySortIndex: members.map(\.librarySortIndex).min() ?? 0,
                isNSFW: customCover == nil && (
                    storedCover.map { $0.nsfw == MangaContentRating.nsfw.rawValue }
                        ?? coverMember?.isNSFW
                        ?? members[0].isNSFW
                )
            ))
        }

        return result.sorted { lhs, rhs in
            switch sortMethod {
                case .alphabetical:
                    let comparison = (lhs.title ?? "").localizedStandardCompare(rhs.title ?? "")
                    return sortAscending ? comparison == .orderedDescending : comparison == .orderedAscending
                case .unreadChapters:
                    return sortAscending ? lhs.unread < rhs.unread : lhs.unread > rhs.unread
                case .lastRead, .lastOpened, .lastUpdated, .dateAdded, .lastChapter:
                    let lhsDate: Date? = switch sortMethod {
                        case .lastRead: lhs.lastRead
                        case .lastOpened: lhs.libraryLastOpened
                        case .lastUpdated: lhs.libraryLastUpdated
                        case .dateAdded: lhs.libraryDateAdded
                        case .lastChapter: lhs.libraryLastChapter
                        default: nil
                    }
                    let rhsDate: Date? = switch sortMethod {
                        case .lastRead: rhs.lastRead
                        case .lastOpened: rhs.libraryLastOpened
                        case .lastUpdated: rhs.libraryLastUpdated
                        case .dateAdded: rhs.libraryDateAdded
                        case .lastChapter: rhs.libraryLastChapter
                        default: nil
                    }
                    return sortAscending
                        ? (lhsDate ?? .distantPast) < (rhsDate ?? .distantPast)
                        : (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
                case .totalChapters:
                    return sortAscending
                        ? lhs.totalChapters < rhs.totalChapters
                        : lhs.totalChapters > rhs.totalChapters
            }
        }
    }

    private func stackMatchesActiveFilters(
        _ stack: LibraryStack,
        infoByID: [MangaIdentifier: MangaInfo]
    ) -> Bool {
        guard !activeFilters.isEmpty else { return true }
        let context = CoreDataManager.shared.container.viewContext
        let objects = stack.members.compactMap { identifier in
            CoreDataManager.shared.getManga(mangaId: identifier, context: context)
        }
        guard !objects.isEmpty else { return false }

        func matches(_ filter: LibraryFilter, manga: MangaObject) -> Bool {
            let identifier = manga.identifier
            let info = infoByID[identifier] ?? unfilteredLibraryManga[identifier]
            switch filter.type {
                case .downloaded: return (info?.downloads ?? 0) > 0
                case .tracking: return CoreDataManager.shared.hasTrack(mangaId: identifier, context: context)
                case .hasUnread: return (info?.unread ?? 0) > 0
                case .caughtUp: return (info?.unread ?? 0) == 0
                case .started: return CoreDataManager.shared.hasHistory(mangaId: identifier, context: context)
                case .completed: return manga.status == AidokuRunner.PublishingStatus.completed.rawValue
                case .source: return filter.value == identifier.sourceKey
                case .contentRating:
                    guard let contentRating = filter.value.flatMap(MangaContentRating.init) else {
                        return false
                    }
                    return Int16(contentRating.rawValue) == manga.nsfw
                case .category:
                    let categories = (manga.libraryObject?.categories?.allObjects as? [CategoryObject])?.compactMap(\.title) ?? []
                    return filter.value.map(categories.contains) ?? false
                case .favorite: return favoriteIds.contains(identifier.description)
                case .collection:
                    let memberships = (
                        UserDefaults.standard.dictionary(forKey: "\(identifier.sourceKey).collectionMembership")
                            as? [String: [String]] ?? [:]
                    )[identifier.mangaKey] ?? []
                    return filter.value.map(memberships.contains) ?? false
                case .genre:
                    guard let value = filter.value,
                          let genre = LibraryGenreFilterSettings.matchingGenre(
                            for: value,
                            in: availableGenres,
                            configuration: LibraryGenreFilterSettings.load()
                          ) else { return false }
                    let genres = identifier.sourceKey.hasPrefix(KomgaSourceRunner.sourceKeyPrefix)
                        ? KomgaGenreStore.genres(sourceKey: identifier.sourceKey, mangaKey: identifier.mangaKey)
                        : manga.tags ?? []
                    return genres.contains(where: genre.matches)
            }
        }

        for filter in activeFilters where filter.exclude {
            if objects.allSatisfy({ matches(filter, manga: $0) }) { return false }
        }
        let included = Dictionary(grouping: activeFilters.filter { !$0.exclude }, by: \.type)
        for filters in included.values {
            guard objects.contains(where: { manga in filters.contains { matches($0, manga: manga) } }) else {
                return false
            }
        }
        return true
    }

    // updates unread counts and manga sort order for history change
    func updateHistory(for manga: [MangaInfo], read: Bool) async {
        let currentManga = self.manga + self.pinnedManga + self.continueReadingManga
        let unreadCounts = await withTaskGroup(of: (Int, Int)?.self, returning: [Int: Int].self) { group in
            for item in manga {
                group.addTask {
                    func getUnreadCount() async -> Int {
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            let filters = CoreDataManager.shared.getMangaChapterFilters(
                                mangaId: item.id,
                                context: context
                            )
                            return CoreDataManager.shared.unreadCount(
                                mangaId: item.id,
                                lang: filters.language,
                                scanlators: filters.scanlators,
                                context: context
                            )
                        }
                    }
                    if let info = currentManga.first(where: { $0.id == item.id }) {
                        return (info.hashValue, await getUnreadCount())
                    } else {
                        return nil
                    }
                }
            }
            var ret: [Int: Int] = [:]
            for await result in group {
                guard let result = result else { continue }
                ret[result.0] = result.1
            }
            return ret
        }
        await MainActor.run {
            for count in unreadCounts {
                if let pinnedIndex = pinnedManga.firstIndex(where: { $0.hashValue == count.key }) {
                    pinnedManga[pinnedIndex].unread = count.value
                    if read && sortMethod == .lastRead && pinnedIndex != 0 {
                        let manga = pinnedManga.remove(at: pinnedIndex)
                        pinnedManga.insert(manga, at: 0)
                    }
                } else if let mangaIndex = self.manga.firstIndex(where: { $0.hashValue == count.key }) {
                    self.manga[mangaIndex].unread = count.value
                    if read && sortMethod == .lastRead && mangaIndex != 0 {
                        let manga = self.manga.remove(at: mangaIndex)
                        self.manga.insert(manga, at: 0)
                    }
                }
            }
        }
        if Self.isDedicatedContinueReadingEnabled
            || pinType == .unread
            || activeFilters.contains(where: { $0.type == .hasUnread || $0.type == .caughtUp }) {
            await loadLibrary()
        } else if sortMethod == .unreadChapters {
            await sortLibrary()
        }
    }

    /// History intentionally survives removing a title from the Library, but its
    /// cached manga object does not. Restore missing display metadata through the
    /// source and cache it so the dedicated Continue Reading section can render
    /// the title and cover on this and subsequent loads.
    private func loadNonLibraryContinueReadingMetadata() async -> [MangaIdentifier: Date] {
        let (historyDates, missingIdentifiers) = await CoreDataManager.shared.container.performBackgroundTask {
            @Sendable context in
            var historyDates: [MangaIdentifier: Date] = [:]
            for history in CoreDataManager.shared.getHistory(context: context) {
                let identifier = history.identifier.mangaIdentifier
                guard !CoreDataManager.shared.hasLibraryManga(mangaId: identifier, context: context) else {
                    continue
                }
                let dateRead = history.dateRead ?? .distantPast
                if dateRead > historyDates[identifier, default: .distantPast] {
                    historyDates[identifier] = dateRead
                }
            }
            let missingIdentifiers = historyDates.keys.filter {
                CoreDataManager.shared.getManga(mangaId: $0, context: context) == nil
            }
            return (historyDates, missingIdentifiers)
        }

        let batchSize = 3
        for startIndex in stride(from: 0, to: missingIdentifiers.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, missingIdentifiers.count)
            let batch = Array(missingIdentifiers[startIndex..<endIndex])
            let loadedManga = await withTaskGroup(of: AidokuRunner.Manga?.self) { group in
                for identifier in batch {
                    group.addTask {
                        guard let source = await SourceManager.shared.source(for: identifier.sourceKey) else {
                            return nil
                        }
                        let manga = AidokuRunner.Manga(
                            sourceKey: identifier.sourceKey,
                            key: identifier.mangaKey,
                            title: ""
                        )
                        return try? await source.getMangaUpdate(
                            manga: manga,
                            needsDetails: true,
                            needsChapters: true
                        )
                    }
                }
                return await group.reduce(into: [AidokuRunner.Manga]()) { result, manga in
                    if let manga {
                        result.append(manga)
                    }
                }
            }

            guard !loadedManga.isEmpty else { continue }
            await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                for manga in loadedManga {
                    CoreDataManager.shared.getOrCreateManga(manga, context: context).load(from: manga)
                    if let chapters = manga.chapters {
                        CoreDataManager.shared.setChapters(
                            chapters,
                            mangaId: manga.identifier,
                            context: context
                        )
                    }
                }
                do {
                    try context.save()
                } catch {
                    LogManager.logger.error(
                        "Unable to cache non-library Continue Reading metadata: \(error.localizedDescription)"
                    )
                }
            }
        }

        return historyDates
    }

    func fetchUnreads(skipSortCheck: Bool = false) async {
        if !skipSortCheck && pinType == .unread {
            // re-load library to ensure pinned manga is correct
            return await loadLibrary()
        }

        let currentManga = Array(Dictionary(
            (self.manga + self.pinnedManga + self.continueReadingManga + Array(unfilteredLibraryManga.values))
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        ).values)

        // fetch new unread counts
        let unreadCounts = await withTaskGroup(of: (MangaIdentifier, Int).self) { group in
            var unreadCounts: [MangaIdentifier: Int] = [:]
            for manga in currentManga {
                group.addTask {
                    let context = CoreDataManager.shared.container.newBackgroundContext()
                    return context.performAndWait {
                        let filters = CoreDataManager.shared.getMangaChapterFilters(mangaId: manga.id, context: context)
                        let count = CoreDataManager.shared.unreadCount(
                            mangaId: manga.id,
                            lang: filters.language,
                            scanlators: filters.scanlators,
                            context: context
                        )
                        return (manga.id, count)
                    }
                }
            }
            for await (key, count) in group {
                unreadCounts[key] = count
            }
            return unreadCounts
        }

        // set unread counts
        for (i, manga) in self.manga.enumerated() {
            guard let count = unreadCounts[manga.id] else { continue }
            self.manga[i].unread = count
        }
        for (i, manga) in self.pinnedManga.enumerated() {
            guard let count = unreadCounts[manga.id] else { continue }
            self.pinnedManga[i].unread = count
        }
        for (i, manga) in self.continueReadingManga.enumerated() {
            guard let count = unreadCounts[manga.id] else { continue }
            self.continueReadingManga[i].unread = count
        }
        for identifier in Array(unfilteredLibraryManga.keys) {
            guard let count = unreadCounts[identifier] else { continue }
            unfilteredLibraryManga[identifier]?.unread = count
        }

        // re-sort library if needed
        if !skipSortCheck && sortMethod == .unreadChapters {
            await sortLibrary()
        }
    }

    func fetchUnreads(for identifier: MangaIdentifier) async {
        let unreadCount = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            let filters = CoreDataManager.shared.getMangaChapterFilters(
                mangaId: identifier,
                context: context
            )
            return CoreDataManager.shared.unreadCount(
                mangaId: identifier,
                lang: filters.language,
                scanlators: filters.scanlators,
                context: context
            )
        }
        var didUpdate = false
        if let index = self.manga.firstIndex(where: { $0.id == identifier }) {
            if self.manga[index].unread != unreadCount {
                didUpdate = true
                self.manga[index].unread = unreadCount
            }
        } else if let index = self.pinnedManga.firstIndex(where: { $0.id == identifier }) {
            if self.pinnedManga[index].unread != unreadCount {
                didUpdate = true
                self.pinnedManga[index].unread = unreadCount
            }
        }
        if let index = self.continueReadingManga.firstIndex(where: { $0.id == identifier }) {
            if self.continueReadingManga[index].unread != unreadCount {
                didUpdate = true
                self.continueReadingManga[index].unread = unreadCount
            }
        }
        // re-sort library if needed
        if didUpdate {
            if Self.isDedicatedContinueReadingEnabled || pinType == .unread {
                await loadLibrary()
            } else if sortMethod == .unreadChapters {
                await sortLibrary()
            }
        }
    }

    func fetchDownloadCounts(for identifier: MangaIdentifier? = nil) async {
        var downloadCounts: [MangaIdentifier: Int] = [:]
        if let identifier {
            downloadCounts[identifier] = await DownloadManager.shared.downloadsCount(for: identifier)
        } else {
            let currentManga = Array(Dictionary(
                (self.manga + self.pinnedManga + self.continueReadingManga + Array(unfilteredLibraryManga.values))
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values)
            for manga in currentManga {
                let identifier = manga.id
                downloadCounts[identifier] = await DownloadManager.shared.downloadsCount(for: identifier)
            }
        }
        for (i, manga) in self.pinnedManga.enumerated() {
            if let count = downloadCounts[manga.id] {
                self.pinnedManga[i].downloads = count
            }
        }
        for (i, manga) in self.manga.enumerated() {
            if let count = downloadCounts[manga.id] {
                self.manga[i].downloads = count
            }
        }
        for (i, manga) in self.continueReadingManga.enumerated() {
            if let count = downloadCounts[manga.id] {
                self.continueReadingManga[i].downloads = count
            }
        }
        for identifier in Array(unfilteredLibraryManga.keys) {
            if let count = downloadCounts[identifier] {
                unfilteredLibraryManga[identifier]?.downloads = count
            }
        }
    }

    @MainActor
    func sortLibrary() async {
        switch sortMethod {
            case .alphabetical:
                if sortAscending {
                    pinnedManga.sort { $0.title ?? "" > $1.title ?? "" }
                    manga.sort { $0.title ?? "" > $1.title ?? "" }
                } else {
                    pinnedManga.sort { $0.title ?? "" < $1.title ?? "" }
                    manga.sort { $0.title ?? "" < $1.title ?? "" }
                }

            case .unreadChapters:
                if sortAscending {
                    // Recently Read pins have their own chronological ordering,
                    // independent of the library's selected sort method.
                    if pinType != .started {
                        pinnedManga.sort {
                            if $0.unread == 0 {
                                false
                            } else if $1.unread == 0 {
                                true
                            } else {
                                $0.unread < $1.unread
                            }
                        }
                    }
                    manga.sort {
                        if $0.unread == 0 {
                            false
                        } else if $1.unread == 0 {
                            true
                        } else {
                            $0.unread < $1.unread
                        }
                    }
                } else {
                    if pinType != .started {
                        pinnedManga.sort { $0.unread > $1.unread }
                    }
                    manga.sort { $0.unread > $1.unread }
                }

            default:
                await loadLibrary()
        }

        updateLibrarySortIndices()
    }

    private func updateLibrarySortIndices() {
        let sortedLibrary: [MangaInfo]
        switch sortMethod {
            case .alphabetical:
                sortedLibrary = (libraryPinnedManga + manga).sorted {
                    if sortAscending {
                        ($0.title ?? "") > ($1.title ?? "")
                    } else {
                        ($0.title ?? "") < ($1.title ?? "")
                    }
                }
            case .unreadChapters:
                sortedLibrary = (libraryPinnedManga + manga).sorted {
                    if sortAscending {
                        if $0.unread == 0 { return false }
                        if $1.unread == 0 { return true }
                        return $0.unread < $1.unread
                    }
                    return $0.unread > $1.unread
                }
            default:
                return
        }

        let indices = Dictionary(
            uniqueKeysWithValues: sortedLibrary.enumerated().map { ($0.element.id, $0.offset) }
        )
        for index in libraryPinnedManga.indices {
            libraryPinnedManga[index].librarySortIndex = indices[libraryPinnedManga[index].id] ?? index
        }
        for index in manga.indices {
            manga[index].librarySortIndex = indices[manga[index].id] ?? index
        }
    }

    func setSort(method: SortMethod, ascending: Bool) async {
        guard sortMethod != method || sortAscending != ascending else {
            return
        }
        if sortAscending != ascending {
            sortAscending = ascending
            if scope == .favorites {
                AppSettings.library.favoritesSortAscending.set(sortAscending)
            } else {
                AppSettings.library.sortAscending.set(sortAscending)
            }
        }
        if sortMethod != method {
            sortMethod = method
            if scope == .favorites {
                AppSettings.library.favoritesSortOption.set(sortMethod.rawValue)
            } else {
                AppSettings.library.sortOption.set(sortMethod.rawValue)
            }
        }
        if pinType == .started {
            // Started titles always use their own Last Read ordering.
            await loadLibrary()
        } else {
            await sortLibrary()
        }
    }

    func toggleFilter(method: LibraryFilter.FilterMethod, value: String? = nil) async {
        let filterIndex = filters.firstIndex(where: { $0.type == method && $0.value == value })
        if method == .genre {
            let wasSelected = filterIndex.map { !filters[$0].exclude } ?? false
            filters.removeAll { $0.type == .genre }
            if !wasSelected {
                filters.append(LibraryFilter(type: method, value: value, exclude: false))
            }
        } else if let filterIndex {
            if filters[filterIndex].exclude {
                filters.remove(at: filterIndex)
            } else {
                filters[filterIndex].exclude = true
            }
        } else if method.defaultsToExcluded {
            filters.append(LibraryFilter(type: method, value: value, exclude: true))
        } else {
            filters.append(LibraryFilter(type: method, value: value, exclude: false))
        }
        await loadLibrary()
    }

    private func saveFilters() {
        let filtersData = try? JSONEncoder().encode(filters)
        if let filtersData {
            if scope == .favorites {
                AppSettings.library.favoritesFiltersData.set(filtersData)
            } else {
                AppSettings.library.filtersData.set(filtersData)
            }
        }
    }

    // returns true if library was reloaded
    @discardableResult
    func mangaOpened(mangaId: MangaIdentifier) async -> Bool {
        guard sortMethod == .lastOpened || pinType.needsUpdateOnContentOpen || Self.isDedicatedContinueReadingEnabled else {
            return false
        }

        if Self.isDedicatedContinueReadingEnabled {
            await loadLibrary()
            return true
        }

        var libraryReloaded = false

        let pinnedIndex = pinnedManga.firstIndex(where: { $0.id == mangaId })
        if let pinnedIndex {
            if pinType.needsUpdateOnContentOpen {
                await loadLibrary()
                libraryReloaded = true
            } else if sortMethod == .lastOpened {
                let manga = pinnedManga.remove(at: pinnedIndex)
                pinnedManga.insert(manga, at: 0)
            } else {
                await loadLibrary() // don't know where to put in manga array, just refresh
                libraryReloaded = true
            }
        } else if pinType.needsUpdateOnContentOpen {
            await loadLibrary()
            libraryReloaded = true
        } else if sortMethod == .lastOpened {
            let index = manga.firstIndex(where: { $0.id == mangaId })
            if let index {
                let manga = manga.remove(at: index)
                if sortAscending {
                    // add to end
                    self.manga.append(manga)
                } else {
                    // add to start
                    self.manga.insert(manga, at: 0)
                }
            }
        }

        return libraryReloaded
    }

    func mangaRead(mangaId: MangaIdentifier) async {
        if Self.isDedicatedContinueReadingEnabled
            || pinType == .started
            || activeFilters.contains(where: { $0.type == .hasUnread || $0.type == .caughtUp }) {
            // reload library in case all chapters were read and the manga should be filtered
            await loadLibrary()
            return
        }

        guard sortMethod == .lastRead else { return }

        if let pinnedIndex = pinnedManga.firstIndex(where: { $0.id == mangaId }) {
            let manga = pinnedManga.remove(at: pinnedIndex)
            self.manga.insert(manga, at: 0)
        } else if let index = manga.firstIndex(where: { $0.id == mangaId }) {
            let manga = manga.remove(at: index)
            self.manga.insert(manga, at: 0)
        }
    }

    func removeFromLibrary(manga: MangaInfo) async {
        pinnedManga.removeAll { $0.id == manga.id }
        continueReadingManga.removeAll { $0.id == manga.id }
        self.manga.removeAll { $0.id == manga.id }
        await MangaManager.shared.removeFromLibrary(mangaId: manga.id)
    }

    func removeFromLibrary(mangaIds: [MangaIdentifier]) async {
        let set = Set(mangaIds)
        pinnedManga.removeAll { set.contains($0.id) }
        continueReadingManga.removeAll { set.contains($0.id) }
        self.manga.removeAll { set.contains($0.id) }
        await MangaManager.shared.removeFromLibrary(mangaIds: mangaIds)
    }

    func addToCurrentCategory(manga: MangaInfo) async {
        guard let currentCategory, isInRealCategory else { return }
        await CoreDataManager.shared.addCategoriesToManga(
            mangaId: manga.id,
            categories: [currentCategory]
        )
    }

    func removeFromCurrentCategory(manga: MangaInfo) async {
        guard let currentCategory, isInRealCategory else { return }
        pinnedManga.removeAll { $0.id == manga.id }
        continueReadingManga.removeAll { $0.id == manga.id }
        self.manga.removeAll { $0.id == manga.id }
        await CoreDataManager.shared.removeCategoriesFromManga(
            mangaId: manga.id,
            categories: [currentCategory]
        )
    }
}
