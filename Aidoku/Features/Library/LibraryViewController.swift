//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/23/22.
//

import UIKit
import LocalAuthentication
import SwiftUI
import AidokuRunner

class LibraryViewController: OldMangaCollectionViewController {

    func scrollToTop(animated: Bool = true) {
        guard isViewLoaded else { return }
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        if collectionView.performSystemScrollToTop(animated: animated) {
            return
        }

        // The adjusted inset only contains the navigation bar's current height.
        // Add the system-reported hidden portion of the bar so the destination
        // is the same fully expanded scroll edge used by a status-bar tap.
        let navigationBar = navigationController?.navigationBar
        let hiddenNavigationBarHeight = navigationBar.map {
            max(0, $0.intrinsicContentSize.height - $0.bounds.height)
        } ?? 0
        let expandedTopInset = collectionView.adjustedContentInset.top + hiddenNavigationBarHeight
        let offset = CGPoint(
            x: -collectionView.adjustedContentInset.left,
            y: -expandedTopInset
        )
        collectionView.setContentOffset(offset, animated: animated)
    }
    let viewModel = LibraryViewModel()

    // MARK: Bar Buttons
    private lazy var downloadBarButton = makeBarButton(
        systemName: "square.and.arrow.down",
        action: #selector(openDownloadQueue),
        titleKey: "DOWNLOAD_QUEUE",
        sharesBackground: false
    )
    private lazy var lockBarButton = makeBarButton(
        systemName: locked ? "lock" : "lock.open",
        action: #selector(performToggleLock),
        titleKey: "TOGGLE_LOCK"
    )
    private lazy var moreBarButton =  makeBarButton(
        systemName: "ellipsis",
        action: nil,
        titleKey: "MORE_BARBUTTON",
        sharesBackground: false
    )
    private lazy var categoryBarButton = makeBarButton(
        systemName: "line.3.horizontal.decrease",
        action: nil,
        titleKey: "CATEGORY",
        sharesBackground: false
    )
    private func makeBarButton(systemName: String? = nil, action: Selector?, titleKey: String, sharesBackground: Bool = true) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: systemName.flatMap { UIImage(systemName: $0) },
            style: .plain,
            target: self,
            action: action
        )
        item.title = NSLocalizedString(titleKey)
        if #available(iOS 26.0, *), !sharesBackground {
            item.sharesBackground = false
        }
        return item
    }

    private lazy var refreshControl = UIRefreshControl()
    private lazy var emptyStackView = EmptyPageStackView()
    private lazy var lockedStackView = LockedPageStackView()

    private lazy var locked = viewModel.isCategoryLocked()
    private var ignoreOptionChange = false
    private var shouldHideRefreshAfterDrag = false
    private var shouldRestoreLargeTitleAfterRefresh = false
    private let refreshDismissalDistance: CGFloat = 44
    private var usesSeparatedPinnedSections = false
    private var isSeparatedPinnedLayoutEnabled: Bool {
        AppSettings.appearance.separatePinnedTitles.get() && viewModel.pinType != .none
    }
    private var showsPinnedSectionTitles: Bool {
        isSeparatedPinnedLayoutEnabled && AppSettings.appearance.showPinnedSectionTitles.get()
    }
    private var keepsPinnedTitlesInLibrary: Bool {
        usesSeparatedPinnedSections && AppSettings.appearance.keepPinnedTitlesInLibrary.get()
    }
    private var shouldShowPinnedPlaceholder: Bool {
        showsPinnedSectionTitles && viewModel.pinnedManga.isEmpty
    }

    private let libraryUndoManager = UndoManager()
    override var undoManager: UndoManager { libraryUndoManager }

    override var usesListLayout: Bool {
        get {
            AppSettings.library.listView.get()
        }
        set {
            AppSettings.library.listView.set(newValue)
        }
    }

    override init() {
        super.init()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Leaving the tab should hide the pull-to-refresh UI without cancelling
        // the refresh task itself.
        refreshControl.endRefreshing()
        shouldHideRefreshAfterDrag = false
        shouldRestoreLargeTitleAfterRefresh = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // fix refresh control snapping height
        refreshControl.didMoveToSuperview()

        // The Library has no text input. Clear any responder retained by the
        // system search tab so opening a menu cannot restore its keyboard.
        view.window?.endEditing(true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // load stored download queue state on first load
        Task {
            await SourceManager.shared.waitForSourcesLoad() // make sure sources are loaded first
            await DownloadManager.shared.loadQueueState()
        }
    }

    override func configure() {
        super.configure()

        title = NSLocalizedString("LIBRARY")

        navigationController?.navigationBar.prefersLargeTitles = true
        collectionView.contentInset.top = 8

        // navbar buttons
        updateMoreMenu()

        // toolbar buttons (editing)
        let deleteButton = UIBarButtonItem(
            title: nil,
            style: .plain,
            target: self,
            action: #selector(removeSelectedFromLibrary)
        )
        deleteButton.image = UIImage(systemName: "trash")
        if #unavailable(iOS 26.0) {
            deleteButton.tintColor = .systemRed
        }

        let addButton = UIBarButtonItem(
            title: nil,
            style: .plain,
            target: self,
            action: #selector(addSelectedToCategories)
        )
        addButton.image = UIImage(systemName: "folder.badge.plus")

        toolbarItems = [
            deleteButton,
            UIBarButtonItem(systemItem: .flexibleSpace),
            addButton
        ]

        // pull to refresh
        // Keep the system's default indicator color, but ensure the control
        // itself is not dimmed by the surrounding hierarchy.
        refreshControl.alpha = 1
        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh(refreshControl:)), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        collectionView.allowsMultipleSelection = !ProcessInfo.processInfo.isMacCatalystApp
        collectionView.allowsSelectionDuringEditing = true
        collectionView.register(
            LibrarySectionHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: LibrarySectionHeader.reuseIdentifier
        )
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard
                kind == UICollectionView.elementKindSectionHeader,
                let self,
                let section = self.dataSource.snapshot().sectionIdentifiers[safe: indexPath.section]
            else {
                return nil
            }
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: LibrarySectionHeader.reuseIdentifier,
                for: indexPath
            ) as? LibrarySectionHeader
            switch section {
                case .pinned:
                    header?.configure(
                        title: self.pinnedSectionTitle,
                        menu: self.makePinTitlesMenu(forSectionHeader: true)
                    )
                case .regular:
                    header?.configure(title: NSLocalizedString("LIBRARY"))
            }
            return header
        }

        // empty text view
        emptyStackView.isHidden = true
        view.addSubview(emptyStackView)

        // locked text view
        lockedStackView.isHidden = true
        lockedStackView.text = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED")
            : NSLocalizedString("CATEGORY_LOCKED")
        lockedStackView.buttonText = NSLocalizedString("VIEW_LIBRARY")
        lockedStackView.button.addTarget(self, action: #selector(performUnlock), for: .touchUpInside)
        view.addSubview(lockedStackView)

        // load data
        Task {
            // load categories
            await viewModel.refreshCategories(skipDataLoad: true)
            // refresh header
            collectionView.collectionViewLayout = self.makeCollectionViewLayout()
            updateNavbarItems()

            // load library
            await viewModel.loadLibrary()
            updateEmptyStack()
            updateLockState()
        }
    }

    override func constrain() {
        super.constrain()

        emptyStackView.translatesAutoresizingMaskIntoConstraints = false
        lockedStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            emptyStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            lockedStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            lockedStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func observe() {
        super.observe()

        let checkNavbarDownloadButton: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isEditing else { return }
                let shouldShowButton = await DownloadManager.shared.hasQueuedDownloads()
                let index = self.navigationItem.rightBarButtonItems?.firstIndex(of: self.downloadBarButton)
                if shouldShowButton && index == nil {
                    // rightmost button
                    self.navigationItem.rightBarButtonItems?.insert(
                        self.downloadBarButton,
                        at: (self.navigationItem.rightBarButtonItems?.count ?? 1) - 1
                    )
                } else if !shouldShowButton, let index = index {
                    self.navigationItem.rightBarButtonItems?.remove(at: index)
                }
            }
        }
        addObserver(forName: .downloadsQueued, using: checkNavbarDownloadButton)
        addObserver(forName: .downloadCancelled, using: checkNavbarDownloadButton)
        addObserver(forName: .downloadsCancelled, using: checkNavbarDownloadButton)

        let updateDownloadCounts: (Notification) -> Void = { [weak self] notification in
            guard let self else { return }
            if let id = notification.object as? ChapterIdentifier {
                Task {
                    await self.viewModel.fetchDownloadCounts(for: id.mangaIdentifier)
                    self.updateDataSource()
                }
            } else if let id = notification.object as? MangaIdentifier {
                Task {
                    await self.viewModel.fetchDownloadCounts(for: id)
                    self.updateDataSource()
                }
            }
        }
        addObserver(forName: .downloadFinished) { notification in
            checkNavbarDownloadButton(notification)
            updateDownloadCounts(.init(name: .downloadFinished, object: (notification.object as? Download)?.mangaIdentifier))
        }
        addObserver(forName: .downloadRemoved, using: updateDownloadCounts)
        addObserver(forName: .downloadsRemoved, using: updateDownloadCounts)

        addObserver(forName: .updateLibrary) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateEmptyStack()
                self.updateDataSource()
                if self.shouldRestoreLargeTitleAfterRefresh {
                    self.shouldRestoreLargeTitleAfterRefresh = false
                    self.scrollToTop(animated: true)
                }
            }
        }
        addObserver(forName: .genreFilterSettingsChanged) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                let availableValues = Set(self.viewModel.availableGenres.map(\.rawValue))
                self.viewModel.filters.removeAll {
                    $0.type == .genre && !availableValues.contains($0.value ?? "")
                }
                self.updateDataSource()
                self.updateMoreMenu()
            }
        }
        addObserver(forName: .init(AppSettings.library.threeStateFilterMethods.key)) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let twoStateMethods = Set(
                    AppSettings.library.threeStateFilterMethods.get().compactMap { identifier in
                        LibraryFilter.FilterMethod.configurableThreeStateFilterMethods.first {
                            $0.threeStateFilterIdentifier == identifier
                        }
                    }
                )
                self.viewModel.filters.removeAll {
                    LibraryFilter.FilterMethod.configurableThreeStateFilterMethods.contains($0.type)
                        && twoStateMethods.contains($0.type)
                        && !$0.exclude
                }
                await self.viewModel.loadLibrary()
                self.updateDataSource()
                self.updateMoreMenu()
            }
        }
        addObserver(forName: .updateLibraryLock) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.locked = self.viewModel.isCategoryLocked()
                self.updateLockState()
            }
        }
        addObserver(forName: .updateCategories) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.refreshCategories()
                self.collectionView.collectionViewLayout = self.makeCollectionViewLayout()
                self.updateDataSource()
                if !self.isEditing {
                    self.updateToolbar() // show/hide add category button
                }
                self.updateHeaderCategories()
                // update lock state
                if AppSettings.library.lockLibrary.get() {
                    NotificationCenter.default.post(name: .updateLibraryLock, object: nil)
                }
            }
        }
        addObserver(forName: .updateMangaCategories) { [weak self] _ in
            guard let self, self.viewModel.currentCategory != nil else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
                self.updateMoreMenu()
            }
        }
        addObserver(forName: .updateManga) { [weak self] notification in
            guard let self, let id = notification.object as? MangaIdentifier else { return }
            Task {
                let libraryReloaded = if !AppSettings.general.incognitoMode.get() {
                    await self.viewModel.mangaOpened(mangaId: id)
                } else {
                    false
                }
                if !libraryReloaded {
                    if self.viewModel.sortMethod == .lastUpdated || self.viewModel.sortMethod == .lastChapter {
                        // if sorting by updated or last chapter, or pinning updated, we need to reload the library to update the order
                        await self.viewModel.loadLibrary()
                    } else {
                        // otherwise, just update the unread count (in case chapters were added)
                        await self.viewModel.fetchUnreads(for: id)
                    }
                }
                self.updateDataSource()
            }
        }
        addObserver(forName: .openedManga) { [weak self] notification in
            guard let self, let id = notification.object as? MangaIdentifier else { return }
            Task {
                await self.viewModel.mangaOpened(mangaId: id)
                if self.viewModel.pinType == .started {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    await self.viewModel.loadLibrary()
                }
                self.updateDataSource()
            }
        }

        addObserver(forName: AppSettings.library.pinTitles.key) { [weak self] _ in
            guard let self else { return }
            self.viewModel.pinType = self.viewModel.getPinType()
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
                self.updateMoreMenu()
            }
        }
        addObserver(forName: AppSettings.library.pinTitlesIgnoreFilters.key) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }
        addObserver(forName: AppSettings.library.pinTitlesIgnoredFilters.key) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }
        addObserver(forName: AppSettings.appearance.separatePinnedTitles.key) { [weak self] _ in
            Task { @MainActor in
                self?.updateDataSource()
            }
        }
        addObserver(forName: AppSettings.appearance.showPinnedSectionTitles.key) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.collectionView.setCollectionViewLayout(self.makeCollectionViewLayout(), animated: false)
                self.updateDataSource()
            }
        }
        addObserver(forName: AppSettings.appearance.keepPinnedTitlesInLibrary.key) { [weak self] _ in
            Task { @MainActor in
                self?.updateDataSource()
            }
        }
        addObserver(forName: AppSettings.appearance.horizontalPinnedTitles.key) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.collectionView.setCollectionViewLayout(self.makeCollectionViewLayout(), animated: false)
            }
        }

        addObserver(forName: .favoriteChanged) { [weak self] _ in
            guard let self, self.viewModel.pinType == .favorites else { return }
            Task { @MainActor in
                await self.viewModel.loadLibrary()
                self.updateDataSource()
            }
        }

        // refresh badges
        addObserver(forName: AppSettings.library.unreadChapterBadges.key) { [weak self] _ in
            if AppSettings.library.unreadChapterBadges.get() {
                self?.viewModel.badgeType.insert(.unread)
            } else {
                self?.viewModel.badgeType.remove(.unread)
            }
            self?.reloadItems()
        }
        addObserver(forName: AppSettings.library.downloadedChapterBadges.key) { [weak self] _ in
            if AppSettings.library.downloadedChapterBadges.get() {
                self?.viewModel.badgeType.insert(.downloaded)
            } else {
                self?.viewModel.badgeType.remove(.downloaded)
            }
            self?.reloadItems()
        }
        addObserver(forName: .filteredChapters) { [weak self] notification in
            guard let self, let id = notification.object as? MangaIdentifier else { return }
            Task {
                await self.viewModel.fetchUnreads(for: id)
                self.updateDataSource()
            }
        }

        // update history
        addObserver(forName: .updateHistory) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.fetchUnreads()
                if self.viewModel.pinType != .unread {
                    await self.viewModel.loadLibrary()
                }
                self.updateDataSource()
            }
        }
        addObserver(forName: .historyAdded) { [weak self] notification in
            guard let self, let chapters = notification.object as? [ChapterIdentifier] else { return }
            Task { @MainActor in
                let manga = Array(Set(chapters.map { MangaInfo(id: $0.mangaIdentifier) }))
                await self.viewModel.updateHistory(for: manga, read: true)
                if self.viewModel.pinType == .started {
                    await self.viewModel.loadLibrary()
                }
                self.updateDataSource()
            }
        }
        addObserver(forName: .historyRemoved) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                var manga: [MangaInfo] = []
                if let chapters = notification.object as? [ChapterIdentifier] {
                    manga = Array(Set(chapters.map { MangaInfo(id: $0.mangaIdentifier) }))
                } else if let mangaId = notification.object as? MangaIdentifier {
                    manga = [MangaInfo(id: mangaId)]
                }
                await self.viewModel.updateHistory(for: manga, read: false)
                if self.viewModel.pinType == .started {
                    await self.viewModel.loadLibrary()
                }
                self.updateDataSource()
            }
        }
        addObserver(forName: .historySet) { [weak self] notification in
            guard let self, let item = notification.object as? (chapterId: ChapterIdentifier, page: Int) else { return }
            Task { @MainActor in
                await self.viewModel.mangaRead(mangaId: item.chapterId.mangaIdentifier)
                self.updateDataSource()
            }
        }

        // lock library when moving to background
        addObserver(forName: UIApplication.willResignActiveNotification) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.locked = self.viewModel.isCategoryLocked()
                self.updateLockState()
            }
        }
    }

    // collection view layout with header
    override func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self else { return nil }
            let isPinnedPlaceholderSection = sectionIndex == 0 && self.shouldShowPinnedPlaceholder
            let usesHorizontalPinnedRow = sectionIndex == 0
                && self.usesSeparatedPinnedSections
                && !self.usesListLayout
                && AppSettings.appearance.horizontalPinnedTitles.get()
            let section = if usesHorizontalPinnedRow {
                Self.makeHorizontalGridLayoutSection(environment: environment)
            } else if self.usesListLayout && !isPinnedPlaceholderSection {
                Self.makeListLayoutSection(environment: environment)
            } else {
                Self.makeGridLayoutSection(environment: environment)
            }
            if self.showsPinnedSectionTitles {
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(48)
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
                section.boundarySupplementaryItems = [header]
            }
            return section
        }
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = if showsPinnedSectionTitles {
            20
        } else if usesSeparatedPinnedSections {
            24
        } else {
            Self.itemSpacing + Self.sectionSpacing
        }
        layout.configuration = config

        return layout
    }

    // cells with badges
    override func configure(cell: MangaGridCell, info: MangaInfo, indexPath: IndexPath) {
        if info.isEmptyPinnedPlaceholder {
            cell.identifier = nil
            cell.setPlaceholder(
                info.title,
                symbolName: pinTypeIconName(for: viewModel.pinType),
                horizontalPadding: AppSettings.appearance.layout.get() == .standard ? 20 : 12
            )
            cell.setEditing(false, animated: false)
            return
        }
        cell.setPlaceholder(nil)
        super.configure(cell: cell, info: info, indexPath: indexPath)

        cell.badgeNumber = viewModel.badgeType.contains(.unread) ? info.unread : 0
        cell.badgeNumber2 = viewModel.badgeType.contains(.downloaded) ? info.downloads : 0

        cell.setEditing(self.isEditing, animated: false)
    }

    override func configure(cell: MangaListCell, info: MangaInfo, indexPath: IndexPath) {
        super.configure(cell: cell, info: info, indexPath: indexPath)

        cell.badgeNumber = viewModel.badgeType.contains(.unread) ? info.unread : 0
        cell.badgeNumber2 = viewModel.badgeType.contains(.downloaded) ? info.downloads : 0

        cell.setEditing(isEditing, animated: false)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        updateNavbarItems()
        updateToolbar()

        if ProcessInfo.processInfo.isMacCatalystApp {
            collectionView.allowsMultipleSelection = editing
        }

        for cell in collectionView.visibleCells {
            if let cell = cell as? MangaGridCell {
                cell.setEditing(editing, animated: animated)
            } else if let cell = cell as? MangaListCell {
                cell.setEditing(editing, animated: animated)
            }
        }
    }
}

extension LibraryViewController {
    func updateNavbarItems() {
        if isEditing {
            let selectableItems = dataSource.snapshot().itemIdentifiers.filter { !$0.isEmptyPinnedPlaceholder }
            let selectedItems = (collectionView.indexPathsForSelectedItems ?? []).compactMap {
                dataSource.itemIdentifier(for: $0)
            }.filter { !$0.isEmptyPinnedPlaceholder }
            let allItemsSelected = !selectableItems.isEmpty && selectedItems.count == selectableItems.count
            navigationItem.leftBarButtonItem = if allItemsSelected {
                makeBarButton(
                    action: #selector(deselectAllItems),
                    titleKey: "DESELECT_ALL"
                )
            } else {
                makeBarButton(
                    action: #selector(selectAllItems),
                    titleKey: "SELECT_ALL"
                )
            }
            navigationItem.rightBarButtonItems = [UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(stopEditing)
            )]
        } else {
            updateCategoryMenu()
            var items: [UIBarButtonItem] = [moreBarButton]
            if viewModel.isCategoryLocked() {
                items.append(lockBarButton)
            }
            navigationItem.rightBarButtonItems = items
            navigationItem.leftBarButtonItem = nil
            Task { @MainActor in
                if await DownloadManager.shared.hasQueuedDownloads() {
                    let index = (navigationItem.rightBarButtonItems?.count ?? 1) - 1
                    guard !(navigationItem.rightBarButtonItems?.contains(downloadBarButton) ?? true) else { return }
                    navigationItem.rightBarButtonItems?.insert(
                        downloadBarButton,
                        at: index
                    )
                }
            }
        }
    }

    private func updateCategoryMenu() {
        var actions: [UIAction] = []
        let all = UIAction(title: NSLocalizedString("ALL"), state: viewModel.currentCategory == nil ? .on : .off) { [weak self] _ in
            self?.optionSelected(IndexPath(row: 0, section: 0))
        }
        actions.append(all)
        if AppSettings.library.showUncategorizedCategory.get() {
            actions.append(UIAction(title: NSLocalizedString("UNCATEGORIZED"), state: viewModel.currentCategory == "" ? .on : .off) { [weak self] _ in
                self?.optionSelected(IndexPath(row: 1, section: 0))
            })
        }
        actions += self.viewModel.categories.enumerated().map { index, category in
            UIAction(title: category, state: self.viewModel.currentCategory == category ? .on : .off) { [weak self] _ in
                self?.optionSelected(IndexPath(row: index, section: 1))
            }
        }
        actions += self.viewModel.filterGroups.enumerated().map { index, group in
            UIAction(title: group.title, state: self.viewModel.currentCategory == group.title ? .on : .off) { [weak self] _ in
                self?.optionSelected(IndexPath(row: index, section: self?.viewModel.categories.isEmpty == true ? 1 : 2))
            }
        }
        categoryBarButton.menu = UIMenu(title: "", children: actions)
    }

    func updateToolbar() {
        if isEditing {
            // show toolbar
            if navigationController?.isToolbarHidden ?? false {
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    self.navigationController?.isToolbarHidden = false
                    self.navigationController?.toolbar.alpha = 1
                    if #available(iOS 26.0, *) {
                        // hide tab bar on iOS 26 (it covers the toolbar)
                        self.tabBarController?.isTabBarHidden = true
                    }
                }
            }
            // show add to category button if categories exist
            if viewModel.categories.isEmpty {
                if #available(iOS 16.0, *) {
                    toolbarItems?.last?.isHidden = true
                } else {
                    toolbarItems?.last?.image = nil
                }
            } else {
                if !self.viewModel.categories.isEmpty {
                    if #available(iOS 16.0, *) {
                        toolbarItems?.last?.isHidden = false
                    } else {
                        toolbarItems?.last?.image = UIImage(systemName: "folder.badge.plus")
                    }
                }
            }
            // enable items
            let hasSelectedItems = !(collectionView.indexPathsForSelectedItems?.isEmpty ?? true)
            toolbarItems?.first?.isEnabled = hasSelectedItems
            toolbarItems?.last?.isEnabled = hasSelectedItems
        } else if !(self.navigationController?.isToolbarHidden ?? true) {
            // fade out toolbar
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.navigationController?.toolbar.alpha = 0
                if #available(iOS 26.0, *) {
                    // reshow tab bar on iOS 26
                    self.tabBarController?.isTabBarHidden = false
                }
            } completion: { _ in
                self.navigationController?.isToolbarHidden = true
            }
        }
    }

    // updates library empty message
    // should be called when category changes and when library loads initially
    func updateEmptyStack() {
        emptyStackView.imageSystemName = "books.vertical.fill"
        emptyStackView.title = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_EMPTY")
            : NSLocalizedString("CATEGORY_EMPTY")
        emptyStackView.text = viewModel.actuallyEmpty
            ? NSLocalizedString("LIBRARY_ADD_CONTENT")
            : NSLocalizedString("LIBRARY_ADJUST_FILTERS")

    }

    @objc func stopEditing() {
        setEditing(false, animated: true)
        deselectAllItems()
    }

    @objc func selectAllItems() {
        for item in dataSource.snapshot().itemIdentifiers where !item.isEmptyPinnedPlaceholder {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
        updateNavbarItems()
        updateToolbar()
        reloadItems()
    }

    @objc func deselectAllItems() {
        for item in dataSource.snapshot().itemIdentifiers {
            if let indexPath = dataSource.indexPath(for: item) {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
        updateNavbarItems()
        updateToolbar()
        reloadItems()
    }

    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl? = nil) {
        let isBlockedByNoWifi = AppSettings.library.updateOnlyOnWifi.get() && Reachability.getConnectionType() != .wifi
        guard !isBlockedByNoWifi else {
            refreshControl?.endRefreshing()
            shouldHideRefreshAfterDrag = false
            presentAlert(
                title: NSLocalizedString("REFRESH_NO_WIFI"),
                message: NSLocalizedString("REFRESH_NO_WIFI_TEXT"),
                actions: [
                    UIAlertAction(title: NSLocalizedString("OK"), style: .cancel),
                    UIAlertAction(title: NSLocalizedString("REFRESH_ANYWAYS"), style: .default) { _ in
                        Task {
                            await MangaManager.shared.backgroundRefreshLibrary(
                                category: self.viewModel.isInRealCategory ? self.viewModel.currentCategory : nil,
                                skipReachabilityCheck: true
                            )
                        }
                    }
                ]
            )
            return
        }

        shouldRestoreLargeTitleAfterRefresh = true
        Task {
            await MangaManager.shared.backgroundRefreshLibrary(
                category: viewModel.isInRealCategory ? viewModel.currentCategory : nil
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                refreshControl?.endRefreshing()
                self.shouldHideRefreshAfterDrag = false
            }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard refreshControl.isRefreshing else { return }
        let top = -scrollView.adjustedContentInset.top
        if scrollView.contentOffset.y > top + refreshDismissalDistance {
            shouldHideRefreshAfterDrag = true
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard shouldHideRefreshAfterDrag else { return }
        shouldHideRefreshAfterDrag = false

        let offset = scrollView.contentOffset
        refreshControl.endRefreshing()
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            scrollView.setContentOffset(offset, animated: false)
        } completion: { _ in
            scrollView.setContentOffset(offset, animated: false)
        }
    }

    @objc func openDownloadQueue() {
        let viewController = UIHostingController(rootView: DownloadQueueView())
        viewController.navigationItem.largeTitleDisplayMode = .never
        viewController.navigationItem.title = NSLocalizedString("DOWNLOAD_QUEUE")
        if #available(iOS 26.0, *) {
            viewController.preferredTransition = .zoom { _ in
                self.downloadBarButton
            }
        }
        viewController.modalPresentationStyle = .pageSheet
        present(viewController, animated: true)
    }

    @objc func removeSelectedFromLibrary() {
        let inCategory = viewModel.isInRealCategory
        let selectedItems = collectionView.indexPathsForSelectedItems ?? []
        confirmAction(
            actions: inCategory ? [
                UIAlertAction(
                    title: NSLocalizedString("REMOVE_FROM_CATEGORY"),
                    style: .destructive
                ) { _ in
                    Task {
                        let identifiers = selectedItems.compactMap { self.dataSource.itemIdentifier(for: $0) }
                        await self.removeFromCategory(mangaInfo: identifiers)?.value
                        self.updateNavbarItems()
                        self.updateToolbar()
                    }
                }
            ] : [],
            continueActionName: NSLocalizedString("REMOVE_FROM_LIBRARY"),
            sourceItem: toolbarItems?.first
        ) {
            Task {
                let identifiers = selectedItems.compactMap { self.dataSource.itemIdentifier(for: $0) }
                await self.removeFromLibrary(mangaInfo: identifiers)?.value
                self.updateNavbarItems()
                self.updateToolbar()
            }
        }
    }

    @objc func addSelectedToCategories() {
        let manga = (collectionView.indexPathsForSelectedItems ?? []).compactMap {
            dataSource.itemIdentifier(for: $0)
        }
        present(
            UINavigationController(rootViewController: AddToCategoryViewController(
                manga: manga,
                disabledCategories: viewModel.isInRealCategory ? [viewModel.currentCategory!] : []
            )),
            animated: true
        )
    }
}

// MARK: - Data Source Updating
extension LibraryViewController {
    func clearDataSource() {
        let snapshot = NSDiffableDataSourceSnapshot<Section, MangaInfo>()
        dataSource.apply(snapshot)
    }

    func updateDataSource() {
        let shouldSeparate = isSeparatedPinnedLayoutEnabled
            && (!viewModel.pinnedManga.isEmpty || AppSettings.appearance.showPinnedSectionTitles.get())
        if usesSeparatedPinnedSections != shouldSeparate {
            usesSeparatedPinnedSections = shouldSeparate
            collectionView.setCollectionViewLayout(makeCollectionViewLayout(), animated: false)
        }

        var snapshot = NSDiffableDataSourceSnapshot<Section, MangaInfo>()

        if !locked {
            if usesSeparatedPinnedSections {
                snapshot.appendSections([.pinned])
                if shouldShowPinnedPlaceholder {
                    snapshot.appendItems([
                        .emptyPinnedPlaceholder(title: emptyPinnedPlaceholderTitle)
                    ], toSection: .pinned)
                } else {
                    snapshot.appendItems(viewModel.pinnedManga, toSection: .pinned)
                }
                let libraryManga = if keepsPinnedTitlesInLibrary {
                    (viewModel.libraryPinnedManga.map { manga in
                        var manga = manga
                        manga.displayVariant = "library"
                        return manga
                    } + viewModel.manga)
                        .sorted { $0.librarySortIndex < $1.librarySortIndex }
                } else {
                    viewModel.manga
                }
                if !libraryManga.isEmpty {
                    snapshot.appendSections([.regular])
                    snapshot.appendItems(libraryManga, toSection: .regular)
                }
            } else {
                snapshot.appendSections([.regular])
                snapshot.appendItems(viewModel.pinnedManga + viewModel.manga, toSection: .regular)
            }
        }

        dataSource.apply(snapshot) { [weak self] in
            self?.updateVisibleSectionHeaders()
        }

        // handle empty library or category
        emptyStackView.isHidden = !snapshot.itemIdentifiers.isEmpty
        collectionView.isScrollEnabled = emptyStackView.isHidden && lockedStackView.isHidden
        collectionView.refreshControl = collectionView.isScrollEnabled ? refreshControl : nil
    }

    private func updateVisibleSectionHeaders() {
        let sections = dataSource.snapshot().sectionIdentifiers
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(
            ofKind: UICollectionView.elementKindSectionHeader
        ) {
            guard
                let section = sections[safe: indexPath.section],
                let header = collectionView.supplementaryView(
                    forElementKind: UICollectionView.elementKindSectionHeader,
                    at: indexPath
                ) as? LibrarySectionHeader
            else {
                continue
            }
            switch section {
                case .pinned:
                    header.configure(
                        title: pinnedSectionTitle,
                        menu: makePinTitlesMenu(forSectionHeader: true),
                        animated: true
                    )
                case .regular:
                    header.configure(title: NSLocalizedString("LIBRARY"))
            }
        }
    }

    private var pinnedSectionTitle: String {
        viewModel.pinType == .started
            ? NSLocalizedString("CONTINUE_READING")
            : viewModel.pinType.title
    }

    private var emptyPinnedPlaceholderTitle: String {
        switch viewModel.pinType {
            case .none:
                ""
            case .favorites:
                "No Favorites"
            case .started:
                "Nothing to Continue"
            case .unread:
                "No Unread Titles"
            case .completed:
                "No Ended Titles"
            case .updatedChapters:
                "No Updated Titles"
        }
    }

    private func pinTypeIconName(for pinType: LibraryViewModel.PinType) -> String {
        switch pinType {
            case .none: "pin.slash"
            case .favorites: "star"
            case .started: "clock"
            case .unread: "eye.slash"
            case .completed: "checkmark.circle"
            case .updatedChapters: "clock.arrow.circlepath"
        }
    }

    func reloadItems() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot)
    }
}

private final class LibrarySectionHeader: UICollectionReusableView {
    static let reuseIdentifier = "LibrarySectionHeader"

    private let titleButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero
        configuration.imagePadding = 6
        configuration.imagePlacement = .trailing
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
                for: .systemFont(ofSize: 20, weight: .semibold)
            )
            return attributes
        }
        titleButton.configuration = configuration
        titleButton.titleLabel?.adjustsFontForContentSizeCategory = true
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleButton)
        NSLayoutConstraint.activate([
            titleButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            titleButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    func configure(title: String, menu: UIMenu? = nil, animated: Bool = false) {
        let titleChanged = titleButton.configuration?.title != title
        var configuration = titleButton.configuration
        configuration?.title = title
        let chevronConfiguration = UIImage.SymbolConfiguration(
            pointSize: 10,
            weight: .bold
        )
        configuration?.image = menu == nil
            ? nil
            : UIImage(
                systemName: "chevron.up.chevron.down",
                withConfiguration: chevronConfiguration
            )?.withTintColor(
                UIColor.secondaryLabel.withAlphaComponent(0.7),
                renderingMode: .alwaysOriginal
            )
        let updatedConfiguration = configuration
        if animated && titleChanged {
            UIView.transition(
                with: titleButton,
                duration: 0.2,
                options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent]
            ) {
                self.titleButton.configuration = updatedConfiguration
            }
        } else {
            titleButton.configuration = updatedConfiguration
        }
        titleButton.menu = menu
        titleButton.showsMenuAsPrimaryAction = menu != nil
        titleButton.isUserInteractionEnabled = menu != nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Locking
extension LibraryViewController {
    func lock() {
        locked = true
        updateLockState()
    }

    func unlock() {
        locked = false
        updateLockState()
    }

    func attemptUnlock() async {
        do {
            let success = try await LAContext().evaluatePolicy(
                .defaultPolicy,
                localizedReason: NSLocalizedString("AUTH_FOR_LIBRARY")
            )
            guard success else { return }
        } catch {
            // The error is displayed to users, so we can ignore it.
            return
        }

        unlock()
    }

    @objc func performUnlock() {
        Task {
            await attemptUnlock()
        }
    }

    @objc func performToggleLock() {
        Task {
            if locked {
                await attemptUnlock()
            } else {
                lock()
            }
        }
    }

    func updateLockState() {
        if locked {
            // only update if lock view not already showing
            if emptyStackView.alpha != 0 {
                collectionView.isScrollEnabled = false
                emptyStackView.alpha = 0
                lockedStackView.alpha = 0
                lockedStackView.isHidden = false
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    self.lockedStackView.alpha = 1
                }
            }
        } else {
            collectionView.isScrollEnabled = emptyStackView.isHidden
            lockedStackView.isHidden = true
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.emptyStackView.alpha = 1
            }
        }
        lockBarButton.image = UIImage(systemName: locked ? "lock" : "lock.open")

        lockedStackView.text = viewModel.currentCategory == nil
            ? NSLocalizedString("LIBRARY_LOCKED")
            : NSLocalizedString("CATEGORY_LOCKED")

        updateNavbarLock()
        updateHeaderLockIcons()
        updateDataSource()
    }

    func updateNavbarLock() {
        guard !isEditing else { return }
        let shouldShowLockIcon = viewModel.isCategoryLocked()
        let index = navigationItem.rightBarButtonItems?.firstIndex(of: lockBarButton)
        if shouldShowLockIcon && index == nil {
            if navigationItem.rightBarButtonItems?.count ?? 0 == 0 {
                navigationItem.rightBarButtonItems = [lockBarButton]
            } else {
                navigationItem.rightBarButtonItems?.insert(lockBarButton, at: 1)
            }
        } else if !shouldShowLockIcon, let index {
            navigationItem.rightBarButtonItems?.remove(at: index)
        }
    }

    func updateHeaderLockIcons() {
        guard let header = (collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(index: 0)
        ) as? LibraryCategorySelectionHeader) else {
            return
        }
        if AppSettings.library.lockLibrary.get() {
            let lockedCategories = AppSettings.library.lockedCategories.get()
            header.lockedOptions = [IndexPath(row: 0, section: 0)] + lockedCategories.compactMap { category -> IndexPath? in
                if let index = self.viewModel.categories.firstIndex(of: category) {
                    return IndexPath(row: index, section: 1)
                }
                if let index = self.viewModel.filterGroups.firstIndex(where: { $0.title == category }) {
                    return IndexPath(row: index, section: self.viewModel.categories.isEmpty ? 1 : 2)
                }
                return nil
            }
        } else {
            header.lockedOptions = []
        }
    }

    // update category options in header
    func updateHeaderCategories() {
        guard let header = (collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(index: 0)
        ) as? LibraryCategorySelectionHeader) else {
            return
        }

        ignoreOptionChange = true
        defer { ignoreOptionChange = false }

        var options: [LibraryCategorySelectionHeader.Section] = []
        if AppSettings.library.showUncategorizedCategory.get() {
            options.append(.init(options: [NSLocalizedString("ALL"), NSLocalizedString("UNCATEGORIZED")]))
        } else {
            options.append(.init(options: [NSLocalizedString("ALL")]))
        }
        if !viewModel.categories.isEmpty {
            options.append(.init(title: NSLocalizedString("CATEGORIES"), options: viewModel.categories))
        }
        if !viewModel.filterGroups.isEmpty {
            options.append(.init(title: NSLocalizedString("FILTER_GROUPS"), options: viewModel.filterGroups.map { $0.title }))
        }
        header.options = options

        if let currentCategory = viewModel.currentCategory {
            if let index = viewModel.categories.firstIndex(of: currentCategory) {
                header.setSelectedOption(IndexPath(row: index, section: 1))
            } else if let index = viewModel.filterGroups.firstIndex(where: { $0.title == currentCategory }) {
                header.setSelectedOption(IndexPath(row: index, section: viewModel.categories.isEmpty ? 1 : 2))
            } else if currentCategory.isEmpty {
                header.setSelectedOption(.init(row: 1, section: 0))
            }
        } else {
            header.setSelectedOption(.init(row: 0, section: 0))
        }
    }
}

// MARK: - Sorting and Filtering
extension LibraryViewController {
    func setSort(method: LibraryViewModel.SortMethod, ascending: Bool) {
        Task {
            await viewModel.setSort(method: method, ascending: ascending)
            updateDataSource()
            if #available(iOS 26.0, *) {
                updateSortMenuState()
            } else {
                updateMoreMenu()
            }
        }
    }

    @available(iOS 26.0, *)
    func updateSortMenuState() {
        func updateElement(_ element: UIMenuElement) -> UIMenuElement {
            guard let menu = element as? UIMenu else { return element }
            if menu.title == NSLocalizedString("SORT_BY") {
                menu.subtitle = viewModel.sortMethod.title
                return menu.replacingChildren(menu.children.map { element in
                    guard let inlineMenu = element as? UIMenu else { return element }
                    return inlineMenu.replacingChildren(inlineMenu.children.map { element in
                        guard let action = element as? UIAction else { return element }
                        let method = LibraryViewModel.SortMethod.allCases.first { $0.title == action.title }
                        let isSelected = method == viewModel.sortMethod
                        action.state = isSelected ? .on : .off
                        action.subtitle = isSelected
                            ? viewModel.sortMethod.directionTitle(ascending: viewModel.sortAscending)
                            : nil
                        return action
                    })
                })
            }
            return menu.replacingChildren(menu.children.map(updateElement))
        }

        if let menu = moreBarButton.menu {
            _ = updateElement(menu)
        }

        let contextMenuInteraction = moreBarButton.value(forKey: "_contextMenuInteraction") as? UIContextMenuInteraction
        contextMenuInteraction?.updateVisibleMenu { menu in
            updateElement(menu) as? UIMenu ?? menu
        }
    }

    func toggleFilter(method: LibraryFilter.FilterMethod, value: String? = nil) {
        Task {
            await viewModel.toggleFilter(method: method, value: value)
            updateDataSource()
            if #available(iOS 26.0, *) {
                updateFilterMenuState()
            } else {
                updateMoreMenu()
            }
        }
    }

    func filterState(for method: LibraryFilter.FilterMethod, value: String? = nil) -> UIMenuElement.State {
        if let filter = viewModel.filters.first(where: { $0.type == method && $0.value == value }) {
            filter.exclude ? .mixed : .on
        } else {
            method.defaultsToExcluded ? .on : .off
        }
    }

    func filterValue(for method: LibraryFilter.FilterMethod, title: String) -> String {
        switch method {
            case .source:
                sourceFilterKeys.first { sourceTitle(for: $0) == title } ?? title
            case .contentRating:
                MangaContentRating.allCases.first { $0.title == title }?.stringValue ?? title
            case .genre:
                viewModel.availableGenres.first { $0.title == title }?.rawValue ?? title
            default:
                title
        }
    }

    func sourceTitle(for sourceKey: String) -> String {
        SourceManager.shared.store.source(for: sourceKey)?.name ?? sourceKey
    }

    var sourceFilterKeys: [String] {
        viewModel.sourceKeys.sorted {
            sourceTitle(for: $0).localizedCaseInsensitiveCompare(sourceTitle(for: $1)) == .orderedAscending
        }
    }

    func filterDisplayTitle(for method: LibraryFilter.FilterMethod, value: String) -> String {
        switch method {
            case .source:
                sourceTitle(for: value)
            case .contentRating:
                MangaContentRating(stringValue: value)?.title ?? value
            case .genre:
                viewModel.availableGenres.first { $0.rawValue == value }?.title ?? value
            default:
                value
        }
    }

    func removeFilterAction() -> UIAction {
        UIAction(
            title: NSLocalizedString("REMOVE_FILTER"),
            image: UIImage(systemName: "minus.circle")
        ) { [weak self] _ in
            Task {
                guard let self else { return }
                self.viewModel.filters = []
                await self.viewModel.loadLibrary()
                self.updateDataSource()
                self.updateMoreMenu()
            }
        }
    }

    func filtersSubtitle() -> String? {
        guard !viewModel.filters.isEmpty else { return nil }
        var options: [String] = []
        let menuOrder: [LibraryFilter.FilterMethod] = [
            .favorite,
            .started,
            .caughtUp,
            .completed,
            .genre,
            .contentRating,
            .collection,
            .category,
            .source,
            .downloaded
        ]
        let filterMethods = menuOrder + LibraryFilter.FilterMethod.allCases.filter { !menuOrder.contains($0) }
        for filterMethod in filterMethods {
            let methodFilters = orderedFilters(for: filterMethod)
            guard !methodFilters.isEmpty else { continue }

            // Show each selected value for submenu filters, but keep the other
            // filter types collapsed to one entry (for example, multiple sources).
            let filtersToShow = if filterMethod.usesValueInSubtitle {
                methodFilters
            } else {
                Array(methodFilters.prefix(1))
            }

            for filter in filtersToShow {
                guard options.count < 3 else {
                    options.removeLast() // make subtitle fit in two lines
                    options.append(NSLocalizedString("AND_MORE"))
                    break
                }
                if filter.exclude {
                    let hiddenTitle = if filterMethod.usesValueInSubtitle,
                                         let value = filter.value,
                                         !value.isEmpty {
                        filterDisplayTitle(for: filterMethod, value: value)
                    } else {
                        filterMethod.title
                    }
                    options.append(String(format: NSLocalizedString("NOT_%@"), hiddenTitle))
                } else {
                    let includedTitle = if filterMethod.usesValueInSubtitle,
                                           let value = filter.value,
                                           !value.isEmpty {
                        filterDisplayTitle(for: filterMethod, value: value)
                    } else {
                        filterMethod.title
                    }
                    options.append(includedTitle)
                }
            }

            if options.last == NSLocalizedString("AND_MORE") {
                break
            }
        }
        return options.joined(separator: NSLocalizedString("FILTER_SEPARATOR"))
    }

    private func isFilterVisible(_ method: LibraryFilter.FilterMethod) -> Bool {
        AppSettings.library.visibleFilterMethods.get().contains(String(method.rawValue))
    }

    func filterSubmenuValues(for method: LibraryFilter.FilterMethod) -> [String] {
        switch method {
            case .contentRating:
                MangaContentRating.allCases.map(\.stringValue)
            case .collection:
                viewModel.collections
            case .category:
                viewModel.categories
            case .source:
                sourceFilterKeys
            case .genre:
                viewModel.availableGenres.map(\.rawValue)
            default:
                []
        }
    }

    func orderedFilters(for method: LibraryFilter.FilterMethod) -> [LibraryFilter] {
        let positions = Dictionary(
            uniqueKeysWithValues: filterSubmenuValues(for: method).enumerated().map { ($0.element, $0.offset) }
        )
        return viewModel.filters
            .enumerated()
            .filter { $0.element.type == method }
            .sorted {
                let lhsPosition = positions[$0.element.value ?? ""] ?? .max
                let rhsPosition = positions[$1.element.value ?? ""] ?? .max
                return lhsPosition == rhsPosition ? $0.offset < $1.offset : lhsPosition < rhsPosition
            }
            .map(\.element)
    }

    func filterSubmenuSubtitle(for method: LibraryFilter.FilterMethod) -> String? {
        let filters = orderedFilters(for: method)
        guard !filters.isEmpty else { return nil }

        var options: [String] = []
        for filter in filters {
            guard options.count < 3 else {
                options.removeLast()
                options.append(NSLocalizedString("AND_MORE"))
                break
            }

            let title: String
            if let value = filter.value, !value.isEmpty {
                title = filterDisplayTitle(for: method, value: value)
            } else {
                title = method.title
            }
            options.append(filter.exclude ? String(format: NSLocalizedString("NOT_%@"), title) : title)
        }
        return options.joined(separator: NSLocalizedString("FILTER_SEPARATOR"))
    }

    @available(iOS 26.0, *)
    func updateFilterMenuState() {
        // _contextMenuInteraction only exists on ios 26+
        // a similar thing could probably be achieved on lower versions by putting a UIButton in the bar button custom view
        let contextMenuInteraction = moreBarButton.value(forKey: "_contextMenuInteraction") as? UIContextMenuInteraction
        guard let contextMenuInteraction else { return }

        func updateFilterSubmenu(_ menu: UIMenu) -> UIMenu {
            menu.subtitle = self.filtersSubtitle()

            func updateElement(_ element: UIMenuElement, method: LibraryFilter.FilterMethod? = nil) -> UIMenuElement {
                if let action = element as? UIAction {
                    if let method {
                        action.state = filterState(for: method, value: filterValue(for: method, title: action.title))
                    } else if let method = LibraryFilter.FilterMethod.allCases.first(where: { $0.title == action.title }) {
                        action.state = filterState(for: method)
                    }
                    return action
                }
                guard let submenu = element as? UIMenu else { return element }
                let submenuMethod: LibraryFilter.FilterMethod? = switch submenu.title {
                    case LibraryFilter.FilterMethod.contentRating.title: .contentRating
                    case LibraryFilter.FilterMethod.category.title: .category
                    case LibraryFilter.FilterMethod.source.title: .source
                    case LibraryFilter.FilterMethod.collection.title: .collection
                    case LibraryFilter.FilterMethod.genre.title: .genre
                    default: nil
                }
                if let submenuMethod {
                    submenu.subtitle = self.filterSubmenuSubtitle(for: submenuMethod)
                }
                return submenu.replacingChildren(submenu.children.map {
                    updateElement($0, method: submenuMethod)
                })
            }

            var children = menu.children.map { updateElement($0) }
            children.removeAll { element in
                guard let method = LibraryFilter.FilterMethod.allCases.first(where: { $0.title == element.title }) else {
                    return false
                }
                return !isFilterVisible(method)
            }
            if !self.viewModel.filters.isEmpty,
               !children.contains(where: { $0.title == NSLocalizedString("REMOVE_FILTER") }) {
                children.append(self.removeFilterAction())
            } else if self.viewModel.filters.isEmpty,
                      children.last?.title == NSLocalizedString("REMOVE_FILTER") {
                children.removeLast()
            }
            return menu.replacingChildren(children)
        }

        contextMenuInteraction.updateVisibleMenu { menu in
            if menu.title == NSLocalizedString("BUTTON_FILTER") {
                return updateFilterSubmenu(menu)
            } else if menu.title == LibraryFilter.FilterMethod.contentRating.title {
                menu.subtitle = self.filterSubmenuSubtitle(for: .contentRating)
                return menu.replacingChildren(MangaContentRating.allCases.map { rating in
                    UIAction(
                        title: rating.title,
                        attributes: .keepsMenuPresented,
                        state: self.filterState(for: .contentRating, value: rating.stringValue)
                    ) { [weak self] _ in
                        self?.toggleFilter(method: .contentRating, value: rating.stringValue)
                    }
                })
            } else if menu.title == LibraryFilter.FilterMethod.category.title {
                menu.subtitle = self.filterSubmenuSubtitle(for: .category)
                return menu.replacingChildren(self.viewModel.categories.map { category in
                    UIAction(
                        title: category,
                        attributes: .keepsMenuPresented,
                        state: self.filterState(for: .category, value: category)
                    ) { [weak self] _ in
                        self?.toggleFilter(method: .category, value: category)
                    }
                })
            } else if menu.title == LibraryFilter.FilterMethod.source.title {
                menu.subtitle = self.filterSubmenuSubtitle(for: .source)
                return menu.replacingChildren(self.sourceFilterKeys.map { sourceKey in
                    UIAction(
                        title: self.sourceTitle(for: sourceKey),
                        attributes: .keepsMenuPresented,
                        state: self.filterState(for: .source, value: sourceKey)
                    ) { [weak self] _ in
                        self?.toggleFilter(method: .source, value: sourceKey)
                    }
                })
            } else if menu.title == LibraryFilter.FilterMethod.collection.title {
                menu.subtitle = self.filterSubmenuSubtitle(for: .collection)
                return menu.replacingChildren(self.viewModel.collections.map { collection in
                    UIAction(
                        title: collection,
                        attributes: .keepsMenuPresented,
                        state: self.filterState(for: .collection, value: collection)
                    ) { [weak self] _ in
                        self?.toggleFilter(method: .collection, value: collection)
                    }
                })
            } else if menu.title == LibraryFilter.FilterMethod.genre.title {
                menu.subtitle = self.filterSubmenuSubtitle(for: .genre)
                return menu.replacingChildren(self.viewModel.availableGenres.map { genre in
                    UIAction(
                        title: genre.title,
                        attributes: .keepsMenuPresented,
                        state: self.filterState(for: .genre, value: genre.rawValue)
                    ) { [weak self] _ in
                        self?.toggleFilter(method: .genre, value: genre.rawValue)
                    }
                })
            } else {
                var rootChildren = menu.children.map { element in
                    guard let menu = element as? UIMenu else { return element }
                    if menu.children.first?.title == NSLocalizedString("SORT_BY") {
                        let updatedChildren = menu.children.map { element in
                            if element.title == NSLocalizedString("BUTTON_FILTER"), let menu = element as? UIMenu {
                                updateFilterSubmenu(menu) as UIMenuElement
                            } else {
                                element
                            }
                        }

                        return menu.replacingChildren(updatedChildren)
                    }
                    return element
                }
                rootChildren.removeAll { $0.title == NSLocalizedString("REMOVE_FILTER") }
                return menu.replacingChildren(rootChildren)
            }
        }

        // Keep the single Library menu control on the filter icon.
        moreBarButton.isSelected = false
        moreBarButton.image = UIImage(systemName: "line.3.horizontal.decrease")
    }

    func makePinTitlesMenu(forSectionHeader: Bool = false) -> UIMenu {
        func image(for pinType: LibraryViewModel.PinType) -> UIImage? {
            guard forSectionHeader else { return nil }
            return UIImage(systemName: pinTypeIconName(for: pinType))
        }

        return UIMenu(
            title: forSectionHeader ? "" : NSLocalizedString("PIN_TITLES"),
            subtitle: forSectionHeader || viewModel.pinType == .none ? nil : viewModel.pinType.title,
            image: forSectionHeader ? nil : UIImage(systemName: "pin"),
            children: LibraryViewModel.PinType.allCases
                .filter { $0 != .none }
                .map { pinType in
                    UIAction(
                        title: pinType.title,
                        image: image(for: pinType),
                        state: viewModel.pinType == pinType ? .on : .off
                    ) { [weak self] _ in
                        guard let self else { return }
                        let selectedPinType: LibraryViewModel.PinType = self.viewModel.pinType == pinType ? .none : pinType
                        self.viewModel.pinType = selectedPinType
                        self.updateVisibleSectionHeaders()
                        AppSettings.library.pinTitles.set(selectedPinType.rawValue)
                        Task { @MainActor in
                            await self.viewModel.loadLibrary()
                            self.updateDataSource()
                            self.updateMoreMenu()
                        }
                    }
                }
        )
    }

    func updateMoreMenu() {
        let selectAction = UIAction(
            title: NSLocalizedString("SELECT"),
            image: UIImage(systemName: "checkmark.circle")
        ) { [weak self] _ in
            guard let self else { return }
            self.setEditing(true, animated: true)
        }

        let layoutActions = [
            UIAction(
                title: NSLocalizedString("LAYOUT_GRID"),
                image: UIImage(systemName: "square.grid.2x2"),
                state: usesListLayout ? .off : .on
            ) { [weak self] _ in
                guard let self, self.usesListLayout else { return }
                self.usesListLayout = false
                self.collectionView.setCollectionViewLayout(self.makeCollectionViewLayout(), animated: true)
                self.collectionView.reloadData()
                self.updateMoreMenu()
            },
            UIAction(
                title: NSLocalizedString("LAYOUT_LIST"),
                image: UIImage(systemName: "list.bullet"),
                state: usesListLayout ? .on : .off
            ) { [weak self] _ in
                guard let self, !self.usesListLayout else { return }
                self.usesListLayout = true
                self.collectionView.setCollectionViewLayout(self.makeCollectionViewLayout(), animated: true)
                self.collectionView.reloadData()
                self.updateMoreMenu()
            }
        ]

        let sortMenu = UIMenu(
            title: NSLocalizedString("SORT_BY"),
            subtitle: viewModel.sortMethod.title,
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: [
                UIMenu(options: .displayInline, children: LibraryViewModel.SortMethod.allCases.map { method in
                    let isSelected = viewModel.sortMethod == method
                    return UIAction(
                        title: method.title,
                        subtitle: isSelected
                            ? method.directionTitle(ascending: viewModel.sortAscending)
                            : nil,
                        attributes: .keepsMenuPresented,
                        state: isSelected ? .on : .off
                    ) { [weak self] _ in
                        guard let self else { return }
                        let ascending = self.viewModel.sortMethod == method
                            ? !self.viewModel.sortAscending
                            : false
                        self.setSort(method: method, ascending: ascending)
                    }
                })
            ]
        )

        let filterMenu = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }

            let attributes: UIMenuElement.Attributes = if #available(iOS 16.0, *) {
                .keepsMenuPresented
            } else {
                []
            }
            func filterAction(for method: LibraryFilter.FilterMethod) -> UIAction {
                UIAction(
                    title: method.title,
                    image: method.image,
                    attributes: attributes,
                    state: self.filterState(for: method)
                ) { [weak self] _ in
                    self?.toggleFilter(method: method)
                }
            }
            var filterChildren: [UIMenuElement] = [
                filterAction(for: .favorite),
                filterAction(for: .started),
                filterAction(for: .caughtUp),
                filterAction(for: .completed),
                UIMenu(
                    title: LibraryFilter.FilterMethod.contentRating.title,
                    subtitle: self.filterSubmenuSubtitle(for: .contentRating),
                    image: LibraryFilter.FilterMethod.contentRating.image,
                    children: MangaContentRating.allCases.map { rating in
                        UIAction(
                            title: rating.title,
                            attributes: attributes,
                            state: self.filterState(for: .contentRating, value: rating.stringValue)
                        ) { [weak self] _ in
                            self?.toggleFilter(method: .contentRating, value: rating.stringValue)
                        }
                    }
                ),
                UIMenu(
                    title: LibraryFilter.FilterMethod.collection.title,
                    subtitle: self.filterSubmenuSubtitle(for: .collection),
                    image: LibraryFilter.FilterMethod.collection.image,
                    children: self.viewModel.collections.map { collection in
                        UIAction(
                            title: collection,
                            attributes: attributes,
                            state: self.filterState(for: .collection, value: collection)
                        ) { [weak self] _ in
                            self?.toggleFilter(method: .collection, value: collection)
                        }
                    }
                ),
                UIMenu(
                    title: LibraryFilter.FilterMethod.category.title,
                    subtitle: self.filterSubmenuSubtitle(for: .category),
                    image: LibraryFilter.FilterMethod.category.image,
                    children: self.viewModel.categories.map { category in
                        UIAction(
                            title: category,
                            attributes: attributes,
                            state: self.filterState(for: .category, value: category)
                        ) { [weak self] _ in
                            self?.toggleFilter(method: .category, value: category)
                        }
                    }
                )
            ]
            if self.sourceFilterKeys.count > 1 {
                filterChildren.append(
                    UIMenu(
                        title: LibraryFilter.FilterMethod.source.title,
                        subtitle: self.filterSubmenuSubtitle(for: .source),
                        image: LibraryFilter.FilterMethod.source.image,
                        children: self.sourceFilterKeys.map { sourceKey in
                            UIAction(
                                title: self.sourceTitle(for: sourceKey),
                                attributes: attributes,
                                state: self.filterState(for: .source, value: sourceKey)
                            ) { [weak self] _ in
                                self?.toggleFilter(method: .source, value: sourceKey)
                            }
                        }
                    )
                )
            }
            if !self.viewModel.availableGenres.isEmpty {
                filterChildren.insert(
                    UIMenu(
                        title: LibraryFilter.FilterMethod.genre.title,
                        subtitle: self.filterSubmenuSubtitle(for: .genre),
                        image: LibraryFilter.FilterMethod.genre.image,
                        children: self.viewModel.availableGenres.map { genre in
                            UIAction(
                                title: genre.title,
                                attributes: attributes,
                                state: self.filterState(for: .genre, value: genre.rawValue)
                            ) { [weak self] _ in
                                self?.toggleFilter(method: .genre, value: genre.rawValue)
                            }
                        }
                    ),
                    at: 4
                )
            }
            filterChildren.append(filterAction(for: .downloaded))
            filterChildren.removeAll { element in
                guard let method = LibraryFilter.FilterMethod.allCases.first(where: { $0.title == element.title }) else {
                    return false
                }
                return !self.isFilterVisible(method)
            }

            var filterMenu = UIMenu(
                title: NSLocalizedString("BUTTON_FILTER"),
                subtitle: self.filtersSubtitle(),
                image: UIImage(systemName: "line.3.horizontal.decrease"),
                children: filterChildren
            )
            if !self.viewModel.filters.isEmpty {
                filterMenu = filterMenu.replacingChildren(filterMenu.children + [self.removeFilterAction()])
            }

            let pinTitlesMenu = self.makePinTitlesMenu()

            completion([filterMenu, pinTitlesMenu])
        }

        moreBarButton.menu = UIMenu(
            children: [
                UIMenu(options: .displayInline, children: [selectAction]),
                UIMenu(options: .displayInline, children: layoutActions),
                UIMenu(options: .displayInline, children: [sortMenu, filterMenu])
            ]
        )

        moreBarButton.isSelected = false
        moreBarButton.image = UIImage(systemName: "line.3.horizontal.decrease")
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: LibraryCategorySelectionHeaderDelegate {
    nonisolated func optionSelected(_ indexPath: IndexPath) {
        Task { @MainActor in
            guard !ignoreOptionChange else {
                ignoreOptionChange = false
                return
            }
            if indexPath.section == 0 {
                if indexPath.row == 0 {
                    viewModel.currentCategory = nil
                } else {
                    viewModel.currentCategory = ""
                }
            } else if indexPath.section == 1 && !viewModel.categories.isEmpty {
                viewModel.currentCategory = viewModel.categories[indexPath.row]
            } else if indexPath.section == 2 || (indexPath.section == 1 && viewModel.categories.isEmpty) {
                viewModel.currentCategory = viewModel.filterGroups[indexPath.row].title
            }
            locked = viewModel.isCategoryLocked()
            updateLockState()
            deselectAllItems()
            updateToolbar()
            updateNavbarItems()

            await viewModel.loadLibrary()
            updateEmptyStack()
            updateDataSource()
        }
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController {
    // support two finger drag to select
    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath)?.isEmptyPinnedPlaceholder == false
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath)?.isEmptyPinnedPlaceholder == false
    }

    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        setEditing(true, animated: true)
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard
            let info = dataSource.itemIdentifier(for: indexPath),
            !info.isEmptyPinnedPlaceholder
        else { return }

        if isEditing {
            let cell = collectionView.cellForItem(at: indexPath)
            guard let cell else { return }
            if let cell = cell as? MangaGridCell {
                cell.setSelected(true)
            } else if let cell = cell as? MangaListCell {
                cell.setSelected(true)
            }
            if #available(iOS 17.5, *) {
                UISelectionFeedbackGenerator().selectionChanged(at: cell.center)
            } else {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            updateNavbarItems()
            updateToolbar()
            return
        }

        if AppSettings.library.opensReaderView.get() {
            Task {
                // get next chapter to read
                let (sortedChapters, nextChapter) = await MangaManager.shared.getNextChapter(mangaId: info.id)

                if let chapter = nextChapter {
                    // open reader view
                    guard let source = await SourceManager.shared.source(for: info.id.sourceKey) else {
                        return
                    }
                    let manga = AidokuRunner.Manga(
                        sourceKey: info.id.sourceKey,
                        key: info.id.mangaKey,
                        title: info.title ?? "",
                        chapters: sortedChapters
                    )
                    let readerController = ReaderViewController(
                        source: source,
                        manga: manga,
                        chapter: chapter
                    )
                    let navigationController = ReaderNavigationController(
                        readerViewController: readerController,
                        mangaInfo: info
                    )
                    if #available(iOS 18.0, *) {
                        navigationController.preferredTransition = .zoom { [weak self] _ in
                            self?.libraryTransitionSourceView(for: info.id)
                        }
                    }
                    navigationController.modalPresentationStyle = .fullScreen
                    present(navigationController, animated: true)
                } else {
                    // no chapter to read, open manga page
                    let indexPath = dataSource.indexPath(for: info) ?? indexPath // get new index path in case it changed
                    super.collectionView(collectionView, didSelectItemAt: indexPath)
                }
            }
        } else {
            super.collectionView(collectionView, didSelectItemAt: indexPath)
        }

        if !AppSettings.general.incognitoMode.get() {
            Task {
                await CoreDataManager.shared.setOpened(mangaId: info.id)
                await self.viewModel.mangaOpened(mangaId: info.id)
                self.updateDataSource()
            }
        }

        collectionView.deselectItem(at: indexPath, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if isEditing {
            let cell = collectionView.cellForItem(at: indexPath)
            if let cell = cell as? MangaGridCell {
                cell.setSelected(false)
            } else if let cell = cell as? MangaListCell {
                cell.setSelected(false)
            }
            updateNavbarItems()
            updateToolbar()
        }
    }

    // don't highlighting when selecting during editing
    override func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        guard
            !isEditing,
            dataSource.itemIdentifier(for: indexPath)?.isEmptyPinnedPlaceholder == false
        else { return }
        super.collectionView(collectionView, didHighlightItemAt: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let indexPath = indexPaths.first,
            let manga = dataSource.itemIdentifier(for: indexPath),
            !manga.isEmptyPinnedPlaceholder
        else {
            return nil
        }

        let mangaInfo = indexPaths.compactMap { dataSource.itemIdentifier(for: $0) }

        let contextPreviewController: LibraryPageContextPreviewViewController? = if
            AppSettings.library.contextMenuPagePreviews.get(),
            mangaInfo.count == 1
        {
            // Start preparing the reader as soon as the menu is requested,
            // instead of waiting for UIKit to ask for the visual preview.
            LibraryPageContextPreviewViewController(mangaId: manga.id)
        } else {
            nil
        }

        let previewProvider: UIContextMenuContentPreviewProvider? = contextPreviewController.map { controller in
            { controller }
        }
        let previewIdentifier: NSString? = contextPreviewController == nil ? nil : manga.id.description as NSString
        return UIContextMenuConfiguration(identifier: previewIdentifier, previewProvider: previewProvider) { _ -> UIMenu? in
            var actions: [UIMenuElement] = []
            let singleAttributes = mangaInfo.count > 1
                ? .disabled
                : UIMenuElement.Attributes()

            if let url = manga.url {
                actions.append(UIMenu(identifier: .share, options: .displayInline, children: [
                    UIAction(
                        title: NSLocalizedString("SHARE"),
                        image: UIImage(systemName: "square.and.arrow.up"),
                        attributes: singleAttributes
                    ) { _ in
                        let activityViewController = UIActivityViewController(
                            activityItems: [url],
                            applicationActivities: nil
                        )
                        activityViewController.popoverPresentationController?.sourceView = self.view
                        activityViewController.popoverPresentationController?.sourceRect = collectionView.cellForItem(at: indexPath)?.frame ?? .zero

                        self.present(activityViewController, animated: true)
                    }
                ]))
            }

            if AppSettings.library.opensReaderView.get(), mangaInfo.count == 1 {
                actions.append(UIAction(
                    title: NSLocalizedString("MANGA_INFO"),
                    image: UIImage(systemName: "info.circle"),
                    attributes: singleAttributes
                ) { _ in
                    self.openInfoView(info: mangaInfo[0], zoom: false)
                })
            }

            if mangaInfo.count == 1 {
                let isFavorite = self.viewModel.isFavorite(manga.id)
                actions.append(UIAction(
                    title: NSLocalizedString(isFavorite ? "UNFAVORITE" : "FAVORITE"),
                    image: UIImage(systemName: isFavorite ? "star.slash" : "star")
                ) { _ in
                    self.viewModel.toggleFavorite(manga.id)
                    Task {
                        await self.viewModel.loadLibrary()
                        self.updateDataSource()
                    }
                })
            }

            if !self.viewModel.categories.isEmpty {
                actions.append(UIAction(
                    title: NSLocalizedString("EDIT_CATEGORIES"),
                    image: UIImage(systemName: "folder.badge.gearshape"),
                    attributes: singleAttributes
                ) { _ in
                    let manga = manga.toManga()
                    self.present(
                        UINavigationController(
                            rootViewController: CategorySelectViewController(
                                manga: manga.toNew()
                            )
                        ),
                        animated: true
                    )
                })
            }

            actions.append(UIAction(
                title: NSLocalizedString("MIGRATE"),
                image: UIImage(systemName: "arrow.left.arrow.right")
            ) { _ in
                let manga = mangaInfo.map { $0.toManga().toNew() }
                let migrateView = MigrateSelectDestinationView(
                    selectedSeries: manga,
                    selectedSources: manga.count == 1
                        ? SourceManager.shared.store.source(for: manga[0].sourceKey).flatMap { [$0.toInfo()] } ?? []
                        : []
                )
                let viewController = SwiftUINavigationViewController(rootView: migrateView)
                self.present(viewController, animated: true)
            })

            var bottomMenuChildren: [UIMenuElement] = []

            bottomMenuChildren.append(UIMenu(title: NSLocalizedString("MARK_ALL"), image: UIImage(systemName: "checkmark.circle"), children: [
                // read chapters
                UIAction(title: NSLocalizedString("READ"), image: UIImage(systemName: "checkmark.circle")) { _ in
                    UIApplication.shared.appDelegate?.showLoadingIndicator()

                    Task {
                        for manga in mangaInfo {
                            let manga = manga.toManga()
                            let chapters = await CoreDataManager.shared.getChapters(mangaId: manga.identifier)

                            await HistoryManager.shared.addHistory(
                                mangaId: manga.identifier,
                                chapters: chapters.map { $0.toNew() }
                            )
                        }

                        await UIApplication.shared.appDelegate?.hideLoadingIndicator()
                    }
                },
                // unread chapters
                UIAction(title: NSLocalizedString("UNREAD"), image: UIImage(systemName: "minus.circle")) { _ in
                    UIApplication.shared.appDelegate?.showLoadingIndicator()

                    Task {
                        for manga in mangaInfo {
                            let chapters = await CoreDataManager.shared.getChapters(mangaId: manga.id)
                            await HistoryManager.shared.removeHistory(
                                chapterIds: chapters.map { $0.identifier }
                            )
                        }

                        await UIApplication.shared.appDelegate?.hideLoadingIndicator()
                    }
                }
            ]))

            let downloadAllAction = UIAction(title: NSLocalizedString("ALL")) { _ in
                let downloadOnlyOnWifi = AppSettings.downloads.downloadOnlyOnWifi.get()
                if downloadOnlyOnWifi && Reachability.getConnectionType() == .wifi || !downloadOnlyOnWifi  {
                    Task {
                        for mangaInfo in mangaInfo {
                            await DownloadManager.shared.downloadAll(manga: mangaInfo.toManga().toNew())
                        }
                    }
                } else {
                    self.presentAlert(
                        title: NSLocalizedString("NO_WIFI_ALERT_TITLE"),
                        message: NSLocalizedString("NO_WIFI_ALERT_MESSAGE")
                    )
                }
            }

            let downloadUnreadAction = UIAction(title: NSLocalizedString("UNREAD")) { _ in
                let downloadOnlyOnWifi = AppSettings.downloads.downloadOnlyOnWifi.get()
                if downloadOnlyOnWifi && Reachability.getConnectionType() == .wifi || !downloadOnlyOnWifi  {
                    Task {
                        for manga in mangaInfo {
                            await DownloadManager.shared.downloadUnread(manga: manga.toManga().toNew())
                        }
                    }
                } else {
                    self.presentAlert(
                        title: NSLocalizedString("NO_WIFI_ALERT_TITLE"),
                        message: NSLocalizedString("NO_WIFI_ALERT_MESSAGE")
                    )
                }
            }

            if
                manga.id.sourceKey != LocalSourceRunner.sourceKey,
                SourceManager.shared.store.isInstalled(sourceKey: manga.id.sourceKey)
            {
                bottomMenuChildren.append(UIMenu(
                    title: NSLocalizedString("DOWNLOAD"),
                    image: UIImage(systemName: "arrow.down.circle"),
                    children: [downloadAllAction, downloadUnreadAction]
                ))
            }

            if self.viewModel.isInRealCategory {
                bottomMenuChildren.append(UIAction(
                    title: NSLocalizedString("REMOVE_FROM_CATEGORY"),
                    image: UIImage(systemName: "folder.badge.minus"),
                    attributes: .destructive
                ) { _ in
                    self.removeFromCategory(mangaInfo: mangaInfo)
                })
            }

            bottomMenuChildren.append(UIAction(
                title: NSLocalizedString("REMOVE_FROM_LIBRARY"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self.removeFromLibrary(mangaInfo: mangaInfo)
            })

            actions.append(UIMenu(options: .displayInline, children: bottomMenuChildren))

            return UIMenu(title: "", children: actions)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        self.collectionView(collectionView, contextMenuConfigurationForItemsAt: [indexPath], point: point)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating
    ) {
        guard
            let identifier = configuration.identifier as? String,
            let mangaInfo = dataSource.snapshot().itemIdentifiers.first(where: {
                $0.id.description == identifier
            })
        else { return }

        guard animator.previewViewController is LibraryPageContextPreviewViewController else { return }
        // Let UIKit promote the preview using its native commit transition.
        // The reader is attached after the promotion completes.
        animator.preferredCommitStyle = .pop
        animator.addCompletion { [weak self] in
            guard let self else { return }
            Task {
                guard
                    let target = await LibraryPagePreviewCache.shared.target(for: mangaInfo.id),
                    let source = SourceManager.shared.store.source(for: mangaInfo.id.sourceKey)
                else { return }
                self.openReaderFromContextPreview(
                    for: mangaInfo,
            target: target,
            source: source
                )
            }
        }
    }

    private func openReaderFromContextPreview(
        for mangaInfo: MangaInfo,
        target: LibraryPagePreviewTarget,
        source: AidokuRunner.Source
    ) {
        let readerController = ReaderViewController(
            source: source,
            manga: target.manga,
            chapter: target.chapter,
            startPage: target.pageIndex + 1,
            delaysAutomaticHideControls: true
        )
        let navigationController = ReaderNavigationController(
            readerViewController: readerController,
            mangaInfo: mangaInfo
        )
        if #available(iOS 18.0, *) {
            // The context-menu commit supplies the opening animation; this
            // transition is retained for the reader's dismissal.
            navigationController.preferredTransition = .zoom { [weak self] _ in
                self?.libraryTransitionSourceView(for: mangaInfo.id)
            }
        }
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: false)
    }

    private func libraryTransitionSourceView(for mangaId: MangaIdentifier) -> UIView? {
        let snapshot = dataSource.snapshot()
        let matchingIndexPaths = collectionView.indexPathsForVisibleItems.filter { indexPath in
            dataSource.itemIdentifier(for: indexPath)?.id == mangaId
        }.sorted { lhs, rhs in
            let lhsSection = snapshot.sectionIdentifiers[safe: lhs.section]
            let rhsSection = snapshot.sectionIdentifiers[safe: rhs.section]
            if lhsSection == .pinned, rhsSection != .pinned { return true }
            if lhsSection != .pinned, rhsSection == .pinned { return false }
            return lhs < rhs
        }

        for indexPath in matchingIndexPaths {
            guard let cell = collectionView.cellForItem(at: indexPath) else { continue }
            if let cell = cell as? MangaListCell {
                return cell.coverImageView
            }
            return cell.contentView
        }
        return nil
    }
}

// MARK: - Undoable Methods
extension LibraryViewController {
    struct LibraryRemovalSnapshot {
        let manga: Manga
        let chapters: [Chapter]
        let trackItems: [TrackItem]
        let categories: [String]
    }

    @discardableResult
    func removeFromLibrary(mangaInfo: [MangaInfo]) -> Task<Void, Never>? {
        let mangaCount = mangaInfo.count
        let actionName =
            mangaCount > 1
            ? String(
                format: NSLocalizedString("REMOVING_%i_ITEMS_FROM_LIBRARY"), mangaCount
            ) : NSLocalizedString("REMOVING_(ONE)_ITEM_FROM_LIBRARY")

        let ids = mangaInfo.map(\.id)

        return Task { [weak self] in
            guard let self else { return }

            let removedManga: [LibraryRemovalSnapshot] = await CoreDataManager.shared.container.performBackgroundTask { context in
                ids.compactMap {
                    guard let manga = CoreDataManager.shared.getManga(mangaId: $0, context: context)?.toManga() else {
                        return nil
                    }
                    let chapters = CoreDataManager.shared.getChapters(mangaId: $0, context: context).map { $0.toChapter() }
                    let trackItems = CoreDataManager.shared.getTracks(mangaId: $0, context: context).map { $0.toItem() }
                    let categories = CoreDataManager.shared.getCategories(mangaId: $0, context: context).compactMap { $0.title }
                    return LibraryRemovalSnapshot(
                        manga: manga,
                        chapters: chapters,
                        trackItems: trackItems,
                        categories: categories
                    )
                }
            }

            guard !Task.isCancelled else { return }

            self.undoManager.setActionName(actionName)
            self.undoManager.registerUndo(withTarget: self) { target in
                target.undoManager.registerUndo(withTarget: target) { redoTarget in
                    redoTarget.removeFromLibrary(mangaInfo: mangaInfo)
                }

                Task {
                    for snapshot in removedManga {
                        await MangaManager.shared.restoreToLibrary(
                            manga: snapshot.manga,
                            chapters: snapshot.chapters,
                            trackItems: snapshot.trackItems,
                            categories: snapshot.categories
                        )
                    }

                    NotificationCenter.default.post(name: .updateLibrary, object: nil)
                }
            }

            await self.viewModel.removeFromLibrary(mangaIds: mangaInfo.map { $0.id })
            self.updateDataSource()
        }
    }

    @discardableResult
    func removeFromCategory(mangaInfo: [MangaInfo]) -> Task<Void, Never>? {
        guard let currentCategory = viewModel.currentCategory else { return nil }
        let mangaCount = mangaInfo.count
        let actionName =
            mangaCount > 1
            ? String(
                format: NSLocalizedString("REMOVING_%i_ITEMS_FROM_CATEGORY_%@"),
                mangaCount, currentCategory)
            : String(
                format: NSLocalizedString("REMOVING_(ONE)_ITEM_FROM_CATEGORY_%@"),
                currentCategory)
        undoManager.setActionName(actionName)

        undoManager.registerUndo(withTarget: self) { target in
            target.undoManager.registerUndo(withTarget: target) { redoTarget in
                redoTarget.removeFromCategory(mangaInfo: mangaInfo)
            }

            Task {
                for manga in mangaInfo {
                    await target.viewModel.addToCurrentCategory(manga: manga)
                }

                NotificationCenter.default.post(name: .updateMangaCategories, object: nil)
            }
        }

        return Task { [weak self] in
            guard let self else { return }

            for manga in mangaInfo {
                await self.viewModel.removeFromCurrentCategory(manga: manga)
            }

            self.updateDataSource()
        }
    }
}
