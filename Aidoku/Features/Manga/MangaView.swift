//
//  MangaView.swift
//  Aidoku
//
//  Created by Skitty on 8/14/23.
//

import AidokuRunner
import NukeUI
import SwiftUI
import UIKit

struct MangaView: View {
    private struct ReaderLaunch: Identifiable {
        let id = UUID()
        let chapter: AidokuRunner.Chapter
        let isIncognitoSession: Bool

        init(_ chapter: AidokuRunner.Chapter, incognito: Bool = false) {
            self.chapter = chapter
            self.isIncognitoSession = incognito
        }
    }

    @StateObject private var viewModel: ViewModel
    @ObservedObject private var toolbarTransitionState: MangaToolbarTransitionState

    @State private var targetChapterKey: String?
    @State private var openAction: OpenAction?

    @State private var editMode = EditMode.inactive
    @State private var selectedChapters = Set<String>()

    @State private var showRemoveAllConfirm = false
    @State private var showRemoveSelectedConfirm = false
    @State private var showConnectionAlert = false

    @State private var detailsLoaded = false
    @State private var isOverHero = true
    @State private var heroBottom: CGFloat?
    @State private var backdropDominantColor: UIColor = .black
    @State private var roundsHeaderTopCorners = false
    @State private var originalNavigationTint: UIColor?
    @State private var statusBarStyleOwner = UUID()

    @Environment(\.colorScheme) private var colorScheme

    @State private var loadingAlert: UIAlertController?

    @State private var readerLaunch: ReaderLaunch?

    @StateObject private var developerMode = UserDefaultsBool(key: AppSettings.general.developerMode.key)
    @StateObject private var incognitoMode = UserDefaultsBool(key: AppSettings.general.incognitoMode.key)

    private var path: NavigationCoordinator
    private let readerTransitionSource: ReaderTransitionSource?

    @Namespace private var transitionNamespace

    enum OpenAction: String {
        case read
        case readNext
        case readLatest
    }

    private var usesLightToolbarIcons: Bool {
        if isOverHero && !toolbarTransitionState.isLeaving {
            let headerColor = CoverPalette.headerColor(for: viewModel.manga.cover ?? "", dark: colorScheme == .dark,
                                                       identifier: viewModel.manga.identifier)
                ?? MangaDetailsBackdrop.darkenedBackgroundColor(
                    from: backdropDominantColor, colorScheme: colorScheme
                )
            return !MangaDetailsBackdrop.shouldUseDarkToolbarIcons(over: headerColor)
        }
        return colorScheme == .dark
    }

    private var usesDarkHeaderText: Bool {
        CoverPalette.usesDarkHeaderText(for: viewModel.manga.cover ?? "", dark: colorScheme == .dark,
                                            identifier: viewModel.manga.identifier)
            ?? MangaDetailsBackdrop.shouldUseDarkHeaderText(backdropDominantColor, colorScheme: colorScheme)
    }

    private var headerControlBackgroundColor: Color {
        Color(uiColor: CoverPalette.controlColor(for: viewModel.manga.cover ?? "", dark: colorScheme == .dark,
                                                identifier: viewModel.manga.identifier)
            ?? MangaDetailsBackdrop.controlBackgroundColor(
            from: backdropDominantColor,
            colorScheme: colorScheme,
            usesDarkText: usesDarkHeaderText
        ))
    }

    init(
        source: AidokuRunner.Source? = nil,
        manga: AidokuRunner.Manga,
        path: NavigationCoordinator,
        chapterKey: String? = nil,
        openAction: OpenAction? = nil,
        toolbarTransitionState: MangaToolbarTransitionState = MangaToolbarTransitionState(),
        readerTransitionSource: ReaderTransitionSource? = nil
    ) {
        let source = source ?? SourceManager.shared.store.source(for: manga.sourceKey)
        self._viewModel = StateObject(wrappedValue: ViewModel(source: source, manga: manga))
        self._backdropDominantColor = State(initialValue: CoverPalette.color(for: manga.cover ?? "", identifier: manga.identifier)
            ?? DeveloperMode.color(for: manga.cover ?? ""))
        self.path = path
        self.readerTransitionSource = readerTransitionSource
        self.toolbarTransitionState = toolbarTransitionState
        self._targetChapterKey = State(initialValue: chapterKey)
        self._openAction = State(initialValue: openAction)
    }

    var body: some View {
        let isNumberedOrder = BookGapPresentation.isNumberedOrder(viewModel.chapters)
        let list = ScrollViewReader { proxy in
            List(selection: $selectedChapters) {
                headerView(section: .cover)
                headerView(section: .details)

                if let error = viewModel.error {
                    ErrorView(
                        error: error,
                        restart: { try await viewModel.source?.restart() },
                        retry: {
                            viewModel.error = nil
                            await viewModel.fetchData()
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    if viewModel.initialDataLoaded && viewModel.chapters.isEmpty {
                        VStack(spacing: 4) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 48, weight: .regular))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 12)
                            Text(NSLocalizedString("NO_CHAPTERS_AVAILABLE"))
                                .font(.title2.bold())
                            Text(viewModel.manga.chapters?.isEmpty == false
                                ? NSLocalizedString("CHAPTERS_ADJUST_FILTERS")
                                : NSLocalizedString("CHAPTERS_EMPTY_DESCRIPTION"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 30)
                        .padding(.top, 56)
                        .padding(.bottom, 64)
                        .listRowInsets(.zero)
                        .listRowBackground(Color(uiColor: .systemBackground))
                        .listRowSeparator(.hidden)
                    }

                    ForEach(viewModel.chapters.indices, id: \.self) { index in
                        let chapter = viewModel.chapters[index]
                        let missingBefore = isNumberedOrder && index > 0
                            ? BookGapPresentation.missingCount(between: viewModel.chapters[index - 1], and: chapter)
                            : 0
                        let missingAfter = isNumberedOrder && index + 1 < viewModel.chapters.count
                            ? BookGapPresentation.missingCount(between: chapter, and: viewModel.chapters[index + 1])
                            : 0
                        if missingBefore > 0 {
                            MissingBooksWarningRow(count: missingBefore)
                        }
                        viewForChapter(chapter, index: index, hideBottomSeparator: missingAfter > 0)
                    }

                }

                if !viewModel.otherDownloadedChapters.isEmpty {
                    if !viewModel.chapters.isEmpty || !(viewModel.manga.chapters?.isEmpty ?? true) {
                        bottomSeparator
                    }

                    VStack {
                        HStack {
                            Text(NSLocalizedString("DOWNLOADED_CHAPTERS"))
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        ListDivider()
                    }
                    .listRowInsets(.zero)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    ForEach(viewModel.otherDownloadedChapters.indices, id: \.self) { index in
                        let chapter = viewModel.otherDownloadedChapters[index]
                        viewForChapter(chapter, index: index, secondSection: true)
                    }

                }
                Color.clear
                    .frame(height: 16)
                    .listRowInsets(.zero)
                    .listRowBackground(Color(uiColor: .systemBackground))
                    .listRowSeparator(.hidden)
            }
            // decrease the min row height for the bottom separator/spacing
            .environment(\.defaultMinListRowHeight, 10)
            .listStyle(.plain)
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialogOrAlert(
                NSLocalizedString("REMOVE_ALL_DOWNLOADS"),
                isPresented: $showRemoveAllConfirm,
                actions: {
                    Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                    Button(NSLocalizedString("REMOVE"), role: .destructive) {
                        Task {
                            await DownloadManager.shared.deleteChapters(for: viewModel.manga.identifier)
                        }
                    }
                },
                message: {
                    Text(NSLocalizedString("REMOVE_ALL_DOWNLOADS_CONFIRM"))
                }
            )
            .confirmationDialogOrAlert(
                NSLocalizedString("REMOVE_DOWNLOADS"),
                isPresented: $showRemoveSelectedConfirm,
                actions: {
                    Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                    Button(NSLocalizedString("REMOVE"), role: .destructive) {
                        Task {
                            await DownloadManager.shared.delete(chapters: selectedChapters.map {
                                .init(
                                    sourceKey: viewModel.manga.sourceKey,
                                    mangaKey: viewModel.manga.key,
                                    chapterKey: $0
                                )
                            })
                            withAnimation {
                                editMode = .inactive
                            }
                        }
                    }
                },
                message: {
                    Text(NSLocalizedString("REMOVE_DOWNLOADS_CONFIRM"))
                }
            )
            .alert(
                NSLocalizedString("NO_WIFI_ALERT_TITLE"),
                isPresented: $showConnectionAlert,
                actions: {
                    Button(NSLocalizedString("OK"), role: .cancel) {}
                },
                message: {
                    Text(NSLocalizedString("NO_WIFI_ALERT_MESSAGE"))
                }
            )
            .scrollBackgroundHiddenPlease()
            .background {
                GeometryReader { geometry in
                    let headerHeight = max(
                        0,
                        (heroBottom ?? geometry.frame(in: .global).maxY)
                            - geometry.frame(in: .global).minY
                    )

                    ZStack(alignment: .top) {
                        Color(uiColor: .systemBackground)

                        MangaDetailsBackdrop(
                            source: viewModel.source,
                            coverImage: viewModel.manga.cover ?? "",
                            paletteIdentifier: viewModel.manga.identifier,
                            baseColor: backdropDominantColor,
                            privacyPlaceholder: developerMode.value,
                            roundsTopCorners: roundsHeaderTopCorners && !incognitoMode.value
                        )
                        .frame(height: headerHeight)
                        .frame(maxHeight: .infinity, alignment: .top)

                        MangaHeaderDisplayModeProbe { shouldRoundCorners in
                            guard roundsHeaderTopCorners != shouldRoundCorners else { return }
                            roundsHeaderTopCorners = shouldRoundCorners
                        }
                        .frame(width: 0, height: 0)
                    }
                }
                .ignoresSafeArea()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .toolbarColorScheme(usesLightToolbarIcons ? .dark : .light, for: .navigationBar)
            .onChange(of: usesLightToolbarIcons) { _ in updateNavigationAppearance() }
            .onChange(of: colorScheme) { _ in
                updateNavigationAppearance()
            }
            .onReceive(NotificationCenter.default.publisher(for: CoverPalette.customColorDidChange)) { notification in
                guard let identifier = notification.object as? MangaIdentifier,
                      identifier == viewModel.manga.identifier else { return }
                backdropDominantColor = CoverPalette.color(for: viewModel.manga.cover ?? "", identifier: identifier)
                    ?? DeveloperMode.color(for: viewModel.manga.cover ?? "")
                updateNavigationAppearance()
            }
            .navigationBarBackButtonHidden(editMode == .active)
            .task {
                guard !detailsLoaded else { return }

                await viewModel.checkForCategories()
                await viewModel.markUpdatesViewed()
                await viewModel.fetchDetails()

                if let openAction {
                    switch openAction {
                        case .read:
                            if let targetChapterKey, let chapter = viewModel.chapters.first(where: { $0.key == targetChapterKey }) {
                                readerLaunch = ReaderLaunch(chapter)
                            }
                        case .readNext:
                            if let nextChapter = viewModel.nextChapter {
                                readerLaunch = ReaderLaunch(nextChapter)
                            }
                        case .readLatest:
                            let visibleChapterKeys = Set(viewModel.chapters.map(\.key))
                            if let latestChapter = viewModel.manga.chapters?.first(where: {
                                visibleChapterKeys.contains($0.key)
                            }) ?? viewModel.chapters.first {
                                readerLaunch = ReaderLaunch(latestChapter)
                            }
                    }
                } else if let targetChapterKey {
                    withAnimation {
                        proxy.scrollTo(targetChapterKey, anchor: .center)
                    }
                }
                self.openAction = nil
                self.targetChapterKey = nil

                await viewModel.syncTrackerProgress()

                detailsLoaded = true
            }
            .onAppear {
                viewModel.refreshReadButtonState()
                updateNavigationAppearance()
            }
            .onDisappear {
                if let navigationController = path.navigationController as? NavigationController {
                    navigationController.setStatusBarStyleOverride(nil, owner: statusBarStyleOwner)
                    if #available(iOS 26.0, *) {
                        navigationController.navigationBar.overrideUserInterfaceStyle =
                            navigationController.navigationBar.window?.traitCollection.userInterfaceStyle ?? .unspecified
                        navigationController.navigationBar.tintColor = nil
                    } else if let originalNavigationTint {
                        navigationController.navigationBar.tintColor = originalNavigationTint
                    }
                }
            }
            .onChange(of: editMode) { mode in
                updateNavigationAppearance()
                guard let navigationController = path.rootViewController?.navigationController
                else { return }
                if mode == .active {
                    navigationController.setDismissGesturesEnabled(false)
                    UIView.animate(withDuration: 0.3) {
                        navigationController.isToolbarHidden = false
                        navigationController.toolbar.alpha = 1
                        if #available(iOS 26.0, *) {
                            navigationController.tabBarController?.isTabBarHidden = true
                        }
                    }
                } else {
                    navigationController.setDismissGesturesEnabled(true)
                    UIView.animate(withDuration: 0.3) {
                        navigationController.toolbar.alpha = 0
                        if #available(iOS 26.0, *) {
                            navigationController.tabBarController?.isTabBarHidden = false
                        }
                    } completion: { _ in
                        navigationController.isToolbarHidden = true
                    }
                }
            }
            .fullScreenCover(item: $readerLaunch) { launch in
                SwiftUIReaderNavigationController(
                    source: viewModel.source,
                    manga: {
                        var mangaWithFilteredChapters = viewModel.manga
                        let visibleChapterKeys = Set(viewModel.chapters.map(\.key))
                        let sourceOrderedChapters = viewModel.manga.chapters?.filter {
                            visibleChapterKeys.contains($0.key)
                        } ?? []

                        // The info page may display chapters in either direction,
                        // but reader navigation always expects the source's canonical
                        // descending order. The reader chapter sheet applies the
                        // user's presentation order separately.
                        mangaWithFilteredChapters.chapters = if sourceOrderedChapters.count == viewModel.chapters.count {
                            sourceOrderedChapters
                        } else if viewModel.chapterSortAscending {
                            Array(viewModel.chapters.reversed())
                        } else {
                            viewModel.chapters
                        }
                        return mangaWithFilteredChapters
                    }(),
                    chapter: launch.chapter,
                    transitionSource: readerTransitionSource
                        ?? ReaderTransitionSource(path.navigationController?.topViewController),
                    isIncognitoSession: launch.isIncognitoSession
                )
                .ignoresSafeArea()
                .id(launch.id)
                .navigationTransitionZoom(sourceID: launch.chapter, in: transitionNamespace)
            }
            .environment(\.editMode, $editMode)
            .clearsStaleListSelection(selectedChapters)
        }

        if #available(iOS 26.0, *) {
            list
                .toolbar {
                    toolbarContentiOS26
                }
        } else {
            list
                .toolbar {
                    toolbarContentBase

                    ToolbarItemGroup(placement: .bottomBar) {
                        if editMode == .active {
                            toolbar
                        }
                    }
                }
        }
    }
}

extension MangaView {
    private func updateNavigationAppearance() {
        guard let navigationController = path.navigationController as? NavigationController else { return }
        if originalNavigationTint == nil {
            originalNavigationTint = navigationController.navigationBar.tintColor
        }
        if #available(iOS 26.0, *) {
            // The navigation bar has no visible background, so SwiftUI's toolbar
            // color scheme alone cannot select the light/dark glass appearance.
            navigationController.navigationBar.overrideUserInterfaceStyle = usesLightToolbarIcons ? .dark : .light
            navigationController.navigationBar.tintColor = nil
        } else {
            navigationController.navigationBar.tintColor = editMode == .active
                ? UIColor(Color.accentColor)
                : (usesLightToolbarIcons ? .white : .black)
        }
        let style: UIStatusBarStyle = usesLightToolbarIcons ? .lightContent : .darkContent
        navigationController.setStatusBarStyleOverride(
            style,
            owner: statusBarStyleOwner
        )
    }

    private func updateHeroPosition(_ bottom: CGFloat) {
        guard let navigationBar = path.navigationController?.navigationBar else { return }
        if heroBottom == nil || abs((heroBottom ?? 0) - bottom) >= 0.5 {
            heroBottom = bottom
        }
        let navigationBarBottom = navigationBar.convert(
            CGPoint(x: 0, y: navigationBar.bounds.maxY), to: nil
        ).y
        let overHero = bottom > navigationBarBottom
        if isOverHero != overHero {
            isOverHero = overHero
        }
    }

    func headerView(section: MangaDetailsHeaderView.Section) -> some View {
        MangaDetailsHeaderView(
            section: section,
            source: $viewModel.source,
            manga: $viewModel.manga,
            chapters: $viewModel.chapters,
            nextChapter: $viewModel.nextChapter,
            readingInProgress: $viewModel.readingInProgress,
            allChaptersLocked: $viewModel.allChaptersLocked,
            allChaptersRead: $viewModel.allChaptersRead,
            bookmarked: $viewModel.bookmarked,
            chapterSortOption: $viewModel.chapterSortOption,
            chapterSortAscending: $viewModel.chapterSortAscending,
            filters: $viewModel.chapterFilters,
            langFilter: $viewModel.chapterLangFilter,
            scanlatorFilter: $viewModel.chapterScanlatorFilter,
            chapterTitleDisplayMode: $viewModel.chapterTitleDisplayMode,
            usesDarkHeaderText: usesDarkHeaderText,
            isEnteringTransition: toolbarTransitionState.isEntering,
            headerControlBackgroundColor: headerControlBackgroundColor,
            nsfwBaseColor: backdropDominantColor,
            onCoverDominantColorChange: { color in
                backdropDominantColor = CoverPalette.color(for: viewModel.manga.cover ?? "",
                                                           identifier: viewModel.manga.identifier) ?? color
            },
            onHeroBottomChange: updateHeroPosition,
            onTitlePressed: {
                guard let tabBarController = path.rootViewController?.tabBarController as? TabBarController else {
                    return
                }
                tabBarController.search(for: viewModel.manga.title)
            },
            onReadButtonPressed: {
                if let nextChapter = viewModel.nextChapter {
                    readerLaunch = ReaderLaunch(nextChapter)
                }
            },
            onReadIncognitoPressed: {
                if let nextChapter = viewModel.nextChapter {
                    readerLaunch = ReaderLaunch(nextChapter, incognito: true)
                }
            }
        )
        .environmentObject(path)
        .listRowInsets(.zero)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    var bottomSeparator: some View {
        VStack {
            ListDivider() // final, full width separator
            Color.clear.frame(height: 28) // padding for bottom of list
        }
        .padding(.top, {
            // add a little spacing above on ios 15, since the separator ends up hidden
            if #available(iOS 16.0, *) { 0 } else { 0.5 }
        }())
        .listRowSeparator(.hidden)
        .listRowInsets(.zero)
    }

    @ViewBuilder
    func viewForChapter(
        _ chapter: AidokuRunner.Chapter,
        index: Int,
        secondSection: Bool = false,
        hideBottomSeparator: Bool = false
    ) -> some View {
        let last = index == (secondSection ? viewModel.otherDownloadedChapters : viewModel.chapters).count - 1
        let downloadStatus = viewModel.downloadStatus[chapter.key, default: .none]
        let downloaded = downloadStatus == .finished
        let locked = chapter.locked && !downloaded
        let opacity: Double = if #available(iOS 17.0, *), locked {
            0.5
        } else {
            1
        }

        ChapterCellView(
            source: viewModel.source,
            manga: viewModel.manga,
            sourceKey: viewModel.manga.sourceKey,
            chapter: chapter,
            read: viewModel.readingHistory[chapter.key]?.page == -1,
            page: viewModel.readingHistory[chapter.key]?.page,
            downloadStatus: downloadStatus,
            downloadProgress: viewModel.downloadProgress[chapter.key],
            displayMode: viewModel.chapterTitleDisplayMode,
            isEditing: editMode == .active
        ) {
            if editMode == .inactive {
                readerLaunch = ReaderLaunch(chapter)
            } else {
                if selectedChapters.contains(chapter.key) {
                    selectedChapters.remove(chapter.key)
                } else {
                    selectedChapters.insert(chapter.key)
                }
            }
        } contextMenu: {
            contextMenu(
                chapter: chapter,
                downloadStatus: downloadStatus,
                index: index,
                last: last,
                secondSection: secondSection
            )
        }
        // use equatableview to determine when to refresh the view
        // improves the scrolling performance of the list
        .equatable()
        .listRowInsets(.zero)
        .disabled(locked)
        .opacity(opacity)
        .id(chapter.key)
        .tag(chapter.key, selectable: !locked)
        .matchedTransitionSourcePlease(id: chapter, in: transitionNamespace)
        .listRowSeparator(last || hideBottomSeparator ? .hidden : .visible)
    }

    @ViewBuilder
    func contextMenu(
        chapter: AidokuRunner.Chapter,
        downloadStatus: DownloadStatus,
        index: Int,
        last: Bool,
        secondSection: Bool
    ) -> some View {
        let identifier = ChapterIdentifier(
            sourceKey: viewModel.manga.sourceKey,
            mangaKey: viewModel.manga.key,
            chapterKey: chapter.key
        )

        let hasDownloadButton = viewModel.source != nil && !viewModel.manga.isLocal() && downloadStatus != .finished && downloadStatus != .downloading
        let hasShareButton = downloadStatus == .finished || chapter.url != nil
        Section {
            let inControlGroup = hasDownloadButton && hasShareButton
            let buttons = Group {
                if hasDownloadButton {
                    Button {
                        let downloadOnlyOnWifi = AppSettings.downloads.downloadOnlyOnWifi.get()
                        if
                            downloadOnlyOnWifi && Reachability.getConnectionType() == .wifi
                                || !downloadOnlyOnWifi
                        {
                            Task {
                                await DownloadManager.shared.download(
                                    manga: viewModel.manga,
                                    chapters: [chapter]
                                )
                            }
                        } else {
                            showConnectionAlert = true
                        }
                    } label: {
                        Label(
                            NSLocalizedString("DOWNLOAD"),
                            systemImage: inControlGroup ? "arrow.down.circle.fill" : "arrow.down.circle"
                        )
                    }
                }
                if hasShareButton {
                    Button {
                        showShareSheet(chapter: chapter)
                    } label: {
                        Label(
                            NSLocalizedString("SHARE"),
                            systemImage: inControlGroup ? "square.and.arrow.up.fill" : "square.and.arrow.up"
                        )
                    }
                }
            }
            if inControlGroup {
                ControlGroup {
                    buttons
                }
            } else {
                buttons
            }
        }

        Section {
            Button {
                readerLaunch = ReaderLaunch(chapter, incognito: true)
            } label: {
                Label(NSLocalizedString("READ_INCOGNITO"), systemImage: "eye.slash")
            }
        }

        Section {
            if viewModel.readingHistory[chapter.key]?.page != nil {
                Button {
                    Task {
                        await viewModel.markUnread(chapters: [chapter])
                    }
                } label: {
                    Label(NSLocalizedString("MARK_UNREAD"), systemImage: "minus.circle")
                }
            }
            if viewModel.readingHistory[chapter.key]?.page != -1 {
                Button {
                    Task {
                        await viewModel.markRead(chapters: [chapter])
                    }
                } label: {
                    Label(NSLocalizedString("MARK_READ"), systemImage: "checkmark.circle")
                }
            }
            if !last && !secondSection {
                Menu(NSLocalizedString("MARK_PREVIOUS")) {
                    Button {
                        let chapters = [AidokuRunner.Chapter](viewModel.chapters[
                            index + 1..<viewModel.chapters.count
                        ])
                        Task {
                            await viewModel.markRead(chapters: chapters)
                        }
                    } label: {
                        Label(NSLocalizedString("READ"), systemImage: "checkmark.circle")
                    }
                    Button {
                        let chapters = [AidokuRunner.Chapter](viewModel.chapters[
                            index + 1..<viewModel.chapters.count
                        ])
                        Task {
                            await viewModel.markUnread(chapters: chapters)
                        }
                    } label: {
                        Label(NSLocalizedString("UNREAD"), systemImage: "minus.circle")
                    }
                }
            }
        }

        Section {
            if viewModel.manga.isLocal() {
                // if the chapter is from the local source, add a button to remove it instead of download
                Button(role: .destructive) {
                    Task {
                        await LocalFileManager.shared.removeChapter(
                            mangaId: viewModel.manga.key,
                            chapterId: chapter.key
                        )
                        if let index = viewModel.chapters.firstIndex(of: chapter) {
                            withAnimation {
                                _ = viewModel.chapters.remove(at: index)
                            }
                        }
                    }
                } label: {
                    Label(NSLocalizedString("REMOVE"), systemImage: "trash")
                }
            } else {
                // a failed download leaves a partial chapter on disk, so it is removable in the same
                // way a complete one is; it keeps the download button as well, which retries it
                if downloadStatus == .finished || downloadStatus == .failed {
                    Button(role: .destructive) {
                        Task {
                            await DownloadManager.shared.delete(chapters: [identifier])
                        }
                    } label: {
                        Label(NSLocalizedString("REMOVE_DOWNLOAD"), systemImage: "trash")
                    }
                } else if downloadStatus == .downloading {
                    Button {
                        Task {
                            await DownloadManager.shared.cancelDownload(for: identifier)
                        }
                    } label: {
                        Label(NSLocalizedString("CANCEL_DOWNLOAD"), systemImage: "xmark")
                    }
                }
            }
        }
    }

    @ViewBuilder
    var rightNavbarButton: some View {
        RightNavbarButton(
            viewModel: viewModel,
            refresh: { await viewModel.refresh() },
            usesLightLabel: usesLightToolbarIcons,
            setEditing: { editing in
                // Set the native bar tint before the selection button is created.
                if #unavailable(iOS 26.0) {
                    path.navigationController?.navigationBar.tintColor = editing
                        ? UIColor(Color.accentColor)
                        : (usesLightToolbarIcons ? .white : .black)
                }
                editMode = editing ? .active : .inactive
            },
            markAllRead: {
                let chapters = viewModel.listedChapters
                // only show loading indicator for a larger number of chapters
                if chapters.count > 100 {
                    showLoadingIndicator()
                }
                Task {
                    await viewModel.markRead(chapters: chapters)
                    hideLoadingIndicator()
                }
            },
            markAllUnread: {
                let chapters = viewModel.listedChapters
                if chapters.count > 100 {
                    showLoadingIndicator()
                }
                Task {
                    await viewModel.markUnread(chapters: chapters)
                    hideLoadingIndicator()
                }
            },
            editCategories: {
                path.present(
                    UINavigationController(
                        rootViewController: CategorySelectViewController(
                            manga: viewModel.manga
                        )
                    )
                )
            },
            migrate: {
                let migrateView = MigrateSelectDestinationView(
                    selectedSeries: [viewModel.manga],
                    selectedSources: viewModel.source.flatMap { [$0.toInfo()] } ?? []
                )
                let viewController = SwiftUINavigationViewController(rootView: migrateView)
                path.present(viewController)
            },
            showShareSheet: showShareSheet(item:),
            openTracker: {
                let vc = TrackerModalViewController(manga: viewModel.manga)
                vc.modalPresentationStyle = .overFullScreen
                path.present(vc, animated: false)
            },
            removeDownloads: {
                showRemoveAllConfirm = true
            },
            editMode: $editMode
        ).equatable()
    }
}

extension MangaView {
    @ToolbarContentBuilder
    var toolbarContentBase: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            let chapters = viewModel.manga.chapters ?? viewModel.chapters
            ChapterListHeaderView(
                allChapters: chapters,
                visibleChapters: viewModel.chapters,
                sortOption: $viewModel.chapterSortOption,
                sortAscending: $viewModel.chapterSortAscending,
                filters: $viewModel.chapterFilters,
                langFilter: $viewModel.chapterLangFilter,
                scanlatorFilter: $viewModel.chapterScanlatorFilter,
                displayMode: $viewModel.chapterTitleDisplayMode,
                mangaId: viewModel.manga.identifier,
                usesLightMenuLabel: usesLightToolbarIcons,
                onReset: { viewModel.resetChapterListPreferences() }
            ).menu
        }

        ToolbarSpacer(placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            rightNavbarButton
        }

        ToolbarItem(placement: .topBarLeading) {
            if editMode == .active {
                // the downloaded chapters section is selectable too, so it has to be counted here
                let selectableCount = viewModel.listedChapters.count
                let allSelected = selectedChapters.count == selectableCount
                Button {
                    if allSelected {
                        selectedChapters = Set()
                    } else {
                        selectedChapters = Set(viewModel.listedChapters.map { $0.key })
                    }
                } label: {
                    Text(NSLocalizedString(allSelected ? "DESELECT_ALL" : "SELECT_ALL"))
                        .foregroundStyle(usesLightToolbarIcons ? Color.white : Color.black)
                }
                .disabled(selectableCount == 0)
            }
        }
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    var toolbarContentiOS26: some ToolbarContent {
        toolbarContentBase

        if editMode == .active {
            ToolbarItem(placement: .bottomBar) {
                toolbarMarkMenu
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)

            if !viewModel.manga.isLocal() {
                ToolbarItem(placement: .bottomBar) {
                    toolbarDownloadButton
                }
            }
        }
    }

    var toolbar: some View {
        HStack {
            toolbarMarkMenu

            Spacer()

            toolbarDownloadButton
        }
    }

    var toolbarMarkMenu: some View {
        Menu(NSLocalizedString("MARK")) {
            let title = if selectedChapters.count == 1 {
                NSLocalizedString("1_CHAPTER")
            } else {
                String(format: NSLocalizedString("%i_CHAPTERS"), selectedChapters.count)
            }
            Section(title) {
                Button {
                    let markChapters = viewModel.chapters(forKeys: selectedChapters)
                    Task {
                        await viewModel.markUnread(chapters: markChapters)
                    }
                    withAnimation {
                        editMode = .inactive
                    }
                } label: {
                    Label(NSLocalizedString("UNREAD"), systemImage: "minus.circle")
                }
                Button {
                    let markChapters = viewModel.chapters(forKeys: selectedChapters)
                    Task {
                        await viewModel.markRead(chapters: markChapters)
                    }
                    withAnimation {
                        editMode = .inactive
                    }
                } label: {
                    Label(NSLocalizedString("READ"), systemImage: "checkmark.circle")
                }
            }
        }
        .disabled(selectedChapters.isEmpty)
    }

    @ViewBuilder
    var toolbarDownloadButton: some View {
        let allChaptersQueued = !selectedChapters.contains(where: {
            viewModel.downloadStatus[$0] != .queued
        })
        let allChaptersDownloaded = !selectedChapters.contains(where: {
            viewModel.downloadStatus[$0] != .finished
        })
        if !selectedChapters.isEmpty && allChaptersQueued {
            Button(NSLocalizedString("CANCEL")) {
                Task { [selectedChapters] in
                    await DownloadManager.shared.cancelDownloads(for: selectedChapters.map {
                        .init(
                            sourceKey: viewModel.manga.sourceKey,
                            mangaKey: viewModel.manga.key,
                            chapterKey: $0
                        )
                    })
                }
                withAnimation {
                    editMode = .inactive
                }
            }
        } else if !selectedChapters.isEmpty && allChaptersDownloaded {
            Button(NSLocalizedString("REMOVE")) {
                showRemoveSelectedConfirm = true
            }
        } else {
            Button(NSLocalizedString("DOWNLOAD")) {
                let downloadChapters = (viewModel.manga.chapters ?? viewModel.chapters)
                    .filter { chapter in
                        let isSelected = selectedChapters.contains(chapter.key)
                        guard isSelected else { return false }
                        let isDownloaded = viewModel.downloadStatus[chapter.key] == .finished
                        let isDownloading = viewModel.downloadStatus[chapter.key] == .downloading
                        let isQueued = viewModel.downloadStatus[chapter.key] == .queued
                        guard !isDownloaded, !isDownloading, !isQueued else { return false }
                        return true
                    }
                    .reversed()

                let downloadOnlyOnWifi = AppSettings.downloads.downloadOnlyOnWifi.get()
                if
                    downloadOnlyOnWifi && Reachability.getConnectionType() == .wifi
                        || !downloadOnlyOnWifi
                {
                    Task {
                        await DownloadManager.shared.download(
                            manga: viewModel.manga,
                            chapters: Array(downloadChapters)
                        )
                    }
                } else {
                    showConnectionAlert = true
                }
                withAnimation {
                    editMode = .inactive
                }
            }
            .disabled(viewModel.source == nil || viewModel.manga.isLocal() || selectedChapters.isEmpty)
        }
    }
}

extension MangaView {
    func showShareSheet(chapter: AidokuRunner.Chapter) {
        if viewModel.downloadStatus[chapter.key] == .finished {
            Task {
                let identifier = ChapterIdentifier(
                    sourceKey: viewModel.manga.sourceKey,
                    mangaKey: viewModel.manga.key,
                    chapterKey: chapter.key
                )
                if let url = await DownloadManager.shared.getCompressedFile(for: identifier) {
                    showShareSheet(item: url)
                }
            }
        } else if let url = chapter.url {
            showShareSheet(item: url)
        }
    }

    func showShareSheet(item: Any) {
        let activityViewController = UIActivityViewController(
            activityItems: [item],
            applicationActivities: nil
        )
        guard let sourceView = path.rootViewController?.view else { return }
        activityViewController.popoverPresentationController?.sourceView = sourceView
        // manually positioned in top right of screen, near the right navigation bar button
        activityViewController.popoverPresentationController?.sourceRect = CGRect(
            x: sourceView.bounds.width - 30,
            y: 60,
            width: 0,
            height: 0
        )
        path.present(activityViewController)
    }

    func showLoadingIndicator() {
        UIApplication.shared.appDelegate?.showLoadingIndicator()
    }

    func hideLoadingIndicator() {
        Task {
            await UIApplication.shared.appDelegate?.hideLoadingIndicator()
        }
    }
}

private struct ChapterCellView<T: View>: View, Equatable {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let sourceKey: String
    let chapter: AidokuRunner.Chapter
    let read: Bool
    let page: Int?
    let downloadStatus: DownloadStatus
    let downloadProgress: Float?
    let displayMode: ChapterTitleDisplayMode
    let isEditing: Bool

    var onPressed: (() -> Void)?
    var contextMenu: (() -> T)?

    private var locked: Bool {
        chapter.locked && !(downloadStatus == .finished)
    }

    private var lockedIndicator: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .frame(width: 36, height: 44)
            .padding(.trailing, 11)
    }

    var body: some View {
        let view = ChapterTableCell(
            source: source,
            manga: manga,
            sourceKey: sourceKey,
            chapter: chapter,
            read: read,
            page: page,
            downloadStatus: downloadStatus,
            downloadProgress: downloadProgress,
            displayMode: displayMode
        )
        if isEditing {
            HStack(spacing: 0) {
                view
                if locked { lockedIndicator }
            }
        } else {
            HStack(spacing: 0) {
                Button {
                    onPressed?()
                } label: {
                    view
                }
                .tint(.primary)
                .contextMenu {
                    if !locked {
                        contextMenu?()
                    }
                } preview: {
                    if AppSettings.library.contextMenuPagePreviews.get() {
                        ChapterPageContextPreview(
                            manga: manga,
                            chapter: chapter,
                            pageIndex: max((page ?? 1) - 1, 0)
                        )
                    } else {
                        view
                    }
                }

                if locked {
                    lockedIndicator
                } else {
                    Menu {
                        contextMenu?()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .frame(width: 36, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.trailing, 11)
                }
            }
        }
    }

    static nonisolated func == (lhs: ChapterCellView<T>, rhs: ChapterCellView<T>) -> Bool {
        lhs.manga.identifier == rhs.manga.identifier
            && lhs.chapter == rhs.chapter
            && lhs.read == rhs.read
            && lhs.page == rhs.page
            && lhs.downloadStatus == rhs.downloadStatus
            && lhs.downloadProgress == rhs.downloadProgress
            && lhs.displayMode == rhs.displayMode
            && lhs.isEditing == rhs.isEditing
    }
}

private struct RightNavbarButton: View, Equatable {
    private let mangaId: MangaIdentifier
    private let bookmarked: Bool
    private let hasCategories: Bool
    private let url: URL?
    private let hasDownloads: Bool
    private let isEditing: Bool
    private let usesLightLabel: Bool
    private let refresh: () async -> Void

    let setEditing: (Bool) -> Void
    let markAllRead: () -> Void
    let markAllUnread: () -> Void
    let editCategories: () -> Void
    let migrate: () -> Void
    let showShareSheet: (URL) -> Void
    let openTracker: () -> Void
    let removeDownloads: () -> Void

    @Binding var editMode: EditMode
    @State private var isFavorite = false
    @State private var hasAvailableTrackers = false

    init(
        viewModel: MangaView.ViewModel,
        refresh: @escaping () async -> Void,
        usesLightLabel: Bool,
        setEditing: @escaping (Bool) -> Void,
        markAllRead: @escaping () -> Void,
        markAllUnread: @escaping () -> Void,
        editCategories: @escaping () -> Void,
        migrate: @escaping () -> Void,
        showShareSheet: @escaping (URL) -> Void,
        openTracker: @escaping () -> Void,
        removeDownloads: @escaping () -> Void,
        editMode: Binding<EditMode>
    ) {
        self.mangaId = viewModel.manga.identifier
        self.usesLightLabel = usesLightLabel
        self.bookmarked = viewModel.bookmarked
        self.hasCategories = viewModel.hasCategories
        self.url = viewModel.manga.url
        self.hasDownloads = viewModel.downloadStatus.contains(where: { $0.value == .finished || $0.value == .failed })
        self.refresh = refresh

        self.setEditing = setEditing
        self.markAllRead = markAllRead
        self.markAllUnread = markAllUnread
        self.editCategories = editCategories
        self.migrate = migrate
        self.showShareSheet = showShareSheet
        self.openTracker = openTracker
        self.removeDownloads = removeDownloads

        self.isEditing = editMode.wrappedValue == .active
        self._editMode = editMode
    }

    var body: some View {
        if editMode == .inactive {
            Menu {
                if bookmarked || hasAvailableTrackers || url != nil {
                    Section {
                        if let url {
                            Button {
                                showShareSheet(url)
                            } label: {
                                Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
                            }
                        }
                        if bookmarked {
                            Button {
                                let identifier = mangaId.description
                                var favoriteIds = Set(UserDefaults.standard.stringArray(forKey: "library.favoriteMangaIdentifiers") ?? [])
                                if !favoriteIds.insert(identifier).inserted {
                                    favoriteIds.remove(identifier)
                                }
                                UserDefaults.standard.set(Array(favoriteIds), forKey: "library.favoriteMangaIdentifiers")
                                isFavorite.toggle()
                                NotificationCenter.default.post(name: .favoriteChanged, object: mangaId)
                            } label: {
                                Label(
                                    NSLocalizedString(isFavorite ? "UNFAVORITE" : "FAVORITE"),
                                    systemImage: isFavorite ? "star.slash" : "star"
                                )
                            }
                        }
                        if hasAvailableTrackers {
                            Button {
                                openTracker()
                            } label: {
                                Label(NSLocalizedString("TRACKING"), systemImage: "clock.arrow.2.circlepath")
                            }
                        }
                    }
                }

                Section {
                    Menu(NSLocalizedString("MARK_ALL")) {
                        Button {
                            markAllRead()
                        } label: {
                            Label(NSLocalizedString("READ"), systemImage: "checkmark.circle")
                        }
                        Button {
                            markAllUnread()
                        } label: {
                            Label(NSLocalizedString("UNREAD"), systemImage: "minus.circle")
                        }
                    }
                    Button {
                        setEditing(true)
                    } label: {
                        Label(NSLocalizedString("SELECT_CHAPTERS"), systemImage: "checkmark.circle")
                    }
                    if bookmarked {
                        if hasCategories {
                            Button {
                                editCategories()
                            } label: {
                                Label(NSLocalizedString("EDIT_CATEGORIES"), systemImage: "folder.badge.gearshape")
                            }
                        }
                        Button {
                            migrate()
                        } label: {
                            Label(NSLocalizedString("MIGRATE"), systemImage: "arrow.left.arrow.right")
                        }
                        if #available(iOS 18.0, *) { // only for system versions supporting swipe down to dismiss
                            Button {
                                Task {
                                    await refresh()
                                }
                            } label: {
                                Label(NSLocalizedString("REFRESH_DETAILS"), systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }

                if hasDownloads {
                    Section {
                        Button(role: .destructive) {
                            removeDownloads()
                        } label: {
                            Label(
                                NSLocalizedString("REMOVE_ALL_DOWNLOADS"),
                                systemImage: "trash"
                            )
                        }
                    }
                }
            } label: {
                MoreIcon()
                    .foregroundStyle(usesLightLabel ? Color.white : Color.black)
            }
            .task(id: mangaId) {
                isFavorite = UserDefaults.standard.stringArray(forKey: "library.favoriteMangaIdentifiers")?
                    .contains(mangaId.description) ?? false
                hasAvailableTrackers = await TrackerManager.shared.hasAvailableTrackers(mangaId: mangaId)
            }
            .onReceive(NotificationCenter.default.publisher(for: .favoriteChanged)) { notification in
                guard let changedId = notification.object as? MangaIdentifier, changedId == mangaId else { return }
                isFavorite = UserDefaults.standard.stringArray(forKey: "library.favoriteMangaIdentifiers")?
                    .contains(mangaId.description) ?? false
            }
        } else {
            DoneButton {
                setEditing(false)
            }
        }

    }

    static nonisolated func == (lhs: RightNavbarButton, rhs: RightNavbarButton) -> Bool {
        lhs.mangaId == rhs.mangaId
            && lhs.bookmarked == rhs.bookmarked
            && lhs.hasCategories == rhs.hasCategories
            && lhs.url == rhs.url
            && lhs.hasDownloads == rhs.hasDownloads
            && lhs.isEditing == rhs.isEditing
            && lhs.usesLightLabel == rhs.usesLightLabel
    }
}

struct MangaDetailsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Style: Equatable {
        case coverColor
        case blurredCover
    }

    let source: AidokuRunner.Source?
    let coverImage: String
    var paletteIdentifier: MangaIdentifier?
    var baseColor: UIColor
    var privacyPlaceholder = false
    var roundsTopCorners = false
    // Switch to `.blurredCover` to restore the previous info-header backdrop.
    var style: Style = .coverColor

    private static func darkening(for colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .dark ? 0.50 : 0.05
    }

    static func darkenedBackgroundColor(from color: UIColor, colorScheme: ColorScheme) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .black
        }
        func scaledColor(_ multiplier: CGFloat) -> UIColor {
            UIColor(red: red * multiplier, green: green * multiplier, blue: blue * multiplier, alpha: 1)
        }
        let darkMultiplier = 1 - darkening(for: .dark)
        let minimumDarkLuminance = 0.015
        let usualDarkBackground = scaledColor(darkMultiplier)
        let adjustedDarkBackground: UIColor
        let darkBackgroundWasLightened: Bool
        if luminance(usualDarkBackground) >= minimumDarkLuminance {
            adjustedDarkBackground = usualDarkBackground
            darkBackgroundWasLightened = false
        } else if luminance(color) >= minimumDarkLuminance {
            // Back off the darkening only as far as needed, preserving the cover's hue.
            var lower = darkMultiplier
            var upper: CGFloat = 1
            for _ in 0..<12 {
                let middle = (lower + upper) / 2
                if luminance(scaledColor(middle)) < minimumDarkLuminance { lower = middle } else { upper = middle }
            }
            adjustedDarkBackground = scaledColor(upper)
            darkBackgroundWasLightened = true
        } else {
            var lower: CGFloat = 0
            var upper: CGFloat = 1
            for _ in 0..<12 {
                let mix = (lower + upper) / 2
                let candidate = UIColor(
                    red: red * (1 - mix) + mix,
                    green: green * (1 - mix) + mix,
                    blue: blue * (1 - mix) + mix,
                    alpha: 1
                )
                if luminance(candidate) < minimumDarkLuminance { lower = mix } else { upper = mix }
            }
            adjustedDarkBackground = UIColor(
                red: red * (1 - upper) + upper,
                green: green * (1 - upper) + upper,
                blue: blue * (1 - upper) + upper,
                alpha: 1
            )
            darkBackgroundWasLightened = true
        }
        guard colorScheme == .light else { return adjustedDarkBackground }

        // Normally derive light mode directly from the sampled cover color.
        // Only link it to dark mode when dark mode had to be lifted to clear its floor.
        var lightRed = red * (1 - darkening(for: .light))
        var lightGreen = green * (1 - darkening(for: .light))
        var lightBlue = blue * (1 - darkening(for: .light))
        if darkBackgroundWasLightened {
            var darkRed: CGFloat = 0
            var darkGreen: CGFloat = 0
            var darkBlue: CGFloat = 0
            guard adjustedDarkBackground.getRed(&darkRed, green: &darkGreen, blue: &darkBlue, alpha: &alpha) else {
                return scaledColor(1 - darkening(for: .light))
            }
            let lightToDarkRatio = (1 - darkening(for: .light)) / darkMultiplier
            lightRed = min(darkRed * lightToDarkRatio, 1)
            lightGreen = min(darkGreen * lightToDarkRatio, 1)
            lightBlue = min(darkBlue * lightToDarkRatio, 1)
        }
        func lightColor(_ multiplier: CGFloat) -> UIColor {
            UIColor(red: lightRed * multiplier, green: lightGreen * multiplier, blue: lightBlue * multiplier, alpha: 1)
        }
        let lightBackground = lightColor(1)
        // Very pale covers need a ceiling rather than a minimum: darken only enough
        // to keep the header from becoming nearly white.
        let maximumLightLuminance = 0.75
        guard luminance(lightBackground) > maximumLightLuminance else { return lightBackground }
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        for _ in 0..<12 {
            let multiplier = (lower + upper) / 2
            if luminance(lightColor(multiplier)) > maximumLightLuminance {
                upper = multiplier
            } else {
                lower = multiplier
            }
        }
        return lightColor(lower)
    }

    static func bottomGradientColor(from background: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard background.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .black
        }
        let brightness = min(max(luminance(background), 0), 1)
        let darkening = 0.02 + 0.08 * (1 - brightness)
        let multiplier = CGFloat(1 - darkening)
        return UIColor(red: red * multiplier, green: green * multiplier, blue: blue * multiplier, alpha: 1)
    }

    private static func luminance(_ background: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard background.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return 0
        }

        func linearComponent(_ value: CGFloat) -> Double {
            let component = Double(max(0, min(1, value)))
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearComponent(red)
            + 0.7152 * linearComponent(green)
            + 0.0722 * linearComponent(blue)
        return luminance
    }

    private static func shouldUseDarkForeground(over background: UIColor) -> Bool {
        let minimumWhiteContrast = 4.5
        let minimumDarkContrast = 4.5
        let darkContrastAdvantage = 6.0
        let backgroundLuminance = luminance(background)
        let whiteContrast = 1.05 / (backgroundLuminance + 0.05)
        let darkContrast = (backgroundLuminance + 0.05) / 0.05
        return whiteContrast < minimumWhiteContrast
            && darkContrast >= minimumDarkContrast
            && darkContrast >= whiteContrast * darkContrastAdvantage
    }

    static func shouldUseDarkHeaderText(_ color: UIColor, colorScheme: ColorScheme) -> Bool {
        let background = darkenedBackgroundColor(from: color, colorScheme: colorScheme)
        return shouldUseDarkForeground(over: background)
    }

    static func shouldUseDarkToolbarIcons(over headerColor: UIColor) -> Bool {
        luminance(headerColor) > 0.4
    }

    static func controlBackgroundColor(
        from color: UIColor,
        colorScheme: ColorScheme,
        usesDarkText: Bool
    ) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let background = darkenedBackgroundColor(from: color, colorScheme: colorScheme)
        guard background.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return usesDarkText ? .lightGray : .darkGray
        }

        // Light headers need a stronger, more opaque shade for their controls;
        // preserve the softer treatment on dark headers.
        let adjustment: CGFloat = 0.17
        func adjusted(_ component: CGFloat) -> CGFloat {
            return usesDarkText
                ? component * (1 - adjustment)
                : component * (1 - adjustment) + adjustment
        }
        return UIColor(
            red: adjusted(red),
            green: adjusted(green),
            blue: adjusted(blue),
            alpha: 0.68
        )
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if style == .coverColor {
                    let background = CoverPalette.headerColor(for: coverImage, dark: colorScheme == .dark,
                                                               identifier: paletteIdentifier)
                        ?? Self.darkenedBackgroundColor(from: baseColor, colorScheme: colorScheme)
                    LinearGradient(
                        stops: [
                            .init(color: Color(uiColor: background), location: 0),
                            .init(color: Color(uiColor: background), location: 0.56),
                            .init(color: Color(uiColor: CoverPalette.headerBottomColor(
                                for: coverImage, dark: colorScheme == .dark, identifier: paletteIdentifier
                            ) ?? Self.bottomGradientColor(from: background)), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    SourceImageView(
                        source: source,
                        imageUrl: coverImage,
                        width: geometry.size.width,
                        height: geometry.size.height,
                        downsampleWidth: 180,
                        privacyPlaceholder: privacyPlaceholder,
                        samplesCoverColor: true
                    )
                    .scaleEffect(1.15)
                    .blur(radius: 45, opaque: true)
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.35), .black.opacity(0.58)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: roundsTopCorners ? 39 : 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: roundsTopCorners ? 39 : 0,
                    style: .continuous
                )
            )
        }
        .allowsHitTesting(false)
    }
}

/// Enables screen-corner rounding only when the info view occupies the full display
/// on a device with a system gesture area (rather than a physical Home button).
private struct MangaHeaderDisplayModeProbe: UIViewRepresentable {
    var onChange: (Bool) -> Void

    func makeUIView(context: Context) -> MangaHeaderDisplayModeProbeView {
        let view = MangaHeaderDisplayModeProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: MangaHeaderDisplayModeProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.updateEligibility()
    }
}

private final class MangaHeaderDisplayModeProbeView: UIView {
    var onChange: ((Bool) -> Void)?
    private var lastEligibility = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateEligibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateEligibility()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateEligibility()
    }

    func updateEligibility() {
        guard let window, let screen = window.windowScene?.screen else {
            publish(false)
            return
        }

        let screenBounds = screen.coordinateSpace.bounds
        let windowBoundsOnScreen = window.convert(window.bounds, to: screen.coordinateSpace)
        let tolerance: CGFloat = 1
        let fillsDisplay = abs(windowBoundsOnScreen.minX - screenBounds.minX) <= tolerance
            && abs(windowBoundsOnScreen.minY - screenBounds.minY) <= tolerance
            && abs(windowBoundsOnScreen.maxX - screenBounds.maxX) <= tolerance
            && abs(windowBoundsOnScreen.maxY - screenBounds.maxY) <= tolerance

        // A gesture-indicator inset is present at the bottom in portrait and may
        // move to either side in landscape. The threshold excludes Home-button safe areas.
        let safeArea = window.safeAreaInsets
        let hasGestureIndicator = max(safeArea.bottom, max(safeArea.left, safeArea.right)) >= 24
        publish(fillsDisplay && hasGestureIndicator)
    }

    private func publish(_ eligible: Bool) {
        guard eligible != lastEligibility else { return }
        lastEligibility = eligible
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(eligible)
        }
    }
}
