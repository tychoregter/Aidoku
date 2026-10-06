//
//  MangaDetailsHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import Nuke
import SafariServices
import SwiftUI
import AidokuRunner

struct MangaDetailsHeaderView: View {
    enum Section {
        case cover
        case details
    }

    let section: Section
    @Binding var source: AidokuRunner.Source?

    @Binding var manga: AidokuRunner.Manga
    @Binding var chapters: [AidokuRunner.Chapter]
    @Binding var nextChapter: AidokuRunner.Chapter?
    @Binding var readingInProgress: Bool
    @Binding var allChaptersLocked: Bool
    @Binding var allChaptersRead: Bool
    @Binding var bookmarked: Bool
    @Binding var chapterSortOption: ChapterSortOption
    @Binding var chapterSortAscending: Bool

    @Binding var filters: [ChapterFilterOption]
    @Binding var langFilter: String?
    @Binding var scanlatorFilter: [String]

    @Binding var chapterTitleDisplayMode: ChapterTitleDisplayMode

    var usesDarkHeaderText = false
    var isEnteringTransition = false
    var headerControlBackgroundColor: Color = .white.opacity(0.14)
    var nsfwBaseColor: UIColor?
    var onCoverDominantColorChange: ((UIColor) -> Void)?
    var onHeroBottomChange: ((CGFloat) -> Void)?
    var onTitlePressed: (() -> Void)?
    var onReadButtonPressed: (() -> Void)?

    @EnvironmentObject private var path: NavigationCoordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    @State private var readButtonTitle = NSLocalizedString("LOADING_ELLIPSIS")
    @State private var readButtonSubtitle: String?
    @State private var readButtonDisabled = true
    @State private var isTracking = false
    @State private var showLibraryRemoveConfirm = false
    @State private var hasEditedCover = false
    @State private var checkedCoverIdentifier: MangaIdentifier?
    @State private var showImagePicker = false
    @State private var uploadedCover: UIImage?
    @State private var coverAspectRatio: CGFloat = 2 / 3
    @State private var showAlternateCoverPicker = false
    @State private var themeColorSheet: ThemeColorSheetMode?
    @State private var hasCustomThemeColor = false
    @State private var descriptionExpansionAnimating = false
    @StateObject private var developerMode = UserDefaultsBool(key: AppSettings.general.developerMode.key)
    @StateObject private var hideNSFWCovers = UserDefaultsBool(key: AppSettings.appearance.blurNSFWCovers.key)
    @StateObject private var showGenres = UserDefaultsBool(key: AppSettings.library.showMangaInfoGenres.key)
    @StateObject private var limitGenresToEnabled = UserDefaultsBool(
        key: AppSettings.library.limitMangaInfoGenresToEnabled.key
    )
    @StateObject private var showTags = UserDefaultsBool(key: AppSettings.library.showMangaInfoTags.key)

    private static let coverDimensionBudget: CGFloat = 500
    private var loadingAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    private var coverSize: CGSize {
        let imageRatio = coverAspectRatio.isFinite && coverAspectRatio > 0 ? coverAspectRatio : 2 / 3
        // Keep the displayed frame between 1:2 and 2:1. More extreme images
        // fill and crop within the nearest allowed ratio.
        let ratio = min(max(imageRatio, 1 / 2), 2)
        let width = Self.coverDimensionBudget * ratio / (1 + ratio)
        let height = Self.coverDimensionBudget / (1 + ratio)
        return CGSize(width: width, height: height)
    }

    private var headerTextColor: Color { usesDarkHeaderText ? .black : .white }
    private var controlOutlineColor: Color { headerTextColor.opacity(usesDarkHeaderText ? 0.085 : 0.15) }
    private var readButtonColor: Color { usesDarkHeaderText ? .black : .white }
    private var readButtonTextColor: Color { usesDarkHeaderText ? .white : .black }
    private var hidesNSFWCover: Bool { hideNSFWCovers.value && manga.contentRating == .nsfw }
    private var displayedTitle: String {
        developerMode.value ? DeveloperMode.title(for: String(describing: manga.identifier)) : manga.title
    }

    init(
        section: Section = .details,
        source: Binding<AidokuRunner.Source?>,
        manga: Binding<AidokuRunner.Manga>,
        chapters: Binding<[AidokuRunner.Chapter]>,
        nextChapter: Binding<AidokuRunner.Chapter?>,
        readingInProgress: Binding<Bool>,
        allChaptersLocked: Binding<Bool>,
        allChaptersRead: Binding<Bool>,
        bookmarked: Binding<Bool>,
        chapterSortOption: Binding<ChapterSortOption>,
        chapterSortAscending: Binding<Bool>,
        filters: Binding<[ChapterFilterOption]>,
        langFilter: Binding<String?>,
        scanlatorFilter: Binding<[String]>,
        chapterTitleDisplayMode: Binding<ChapterTitleDisplayMode>,
        usesDarkHeaderText: Bool = false,
        isEnteringTransition: Bool = false,
        headerControlBackgroundColor: Color = .white.opacity(0.14),
        nsfwBaseColor: UIColor? = nil,
        onCoverDominantColorChange: ((UIColor) -> Void)? = nil,
        onHeroBottomChange: ((CGFloat) -> Void)? = nil,
        onTitlePressed: (() -> Void)? = nil,
        onReadButtonPressed: (() -> Void)? = nil
    ) {
        self.section = section
        self._source = source
        self._manga = manga
        self._chapters = chapters
        self._nextChapter = nextChapter
        self._readingInProgress = readingInProgress
        self._allChaptersLocked = allChaptersLocked
        self._allChaptersRead = allChaptersRead
        self._bookmarked = bookmarked
        self._chapterSortOption = chapterSortOption
        self._chapterSortAscending = chapterSortAscending
        self._filters = filters
        self._langFilter = langFilter
        self._scanlatorFilter = scanlatorFilter
        self._chapterTitleDisplayMode = chapterTitleDisplayMode
        self.usesDarkHeaderText = usesDarkHeaderText
        self.isEnteringTransition = isEnteringTransition
        self.headerControlBackgroundColor = headerControlBackgroundColor
        self.nsfwBaseColor = nsfwBaseColor
        self.onCoverDominantColorChange = onCoverDominantColorChange
        self.onHeroBottomChange = onHeroBottomChange
        self.onTitlePressed = onTitlePressed
        self.onReadButtonPressed = onReadButtonPressed

        self._isTracking = State(initialValue: TrackerManager.shared.isTracking(
            mangaId: manga.wrappedValue.identifier
        ))
        self._hasCustomThemeColor = State(initialValue: CoverPalette.customColor(for: manga.wrappedValue.identifier) != nil)
    }

    var body: some View {
        Group {
            if section == .cover {
                coverView
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    heroView

                    ChapterListHeaderView(
                        allChapters: manga.chapters,
                        visibleChapters: chapters,
                        sortOption: $chapterSortOption,
                        sortAscending: $chapterSortAscending,
                        filters: $filters,
                        langFilter: $langFilter,
                        scanlatorFilter: $scanlatorFilter,
                        displayMode: $chapterTitleDisplayMode,
                        mangaId: manga.identifier
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
        }
        .animation(loadingAnimation, value: manga)
        .animation(loadingAnimation, value: source != nil)
        .animation(loadingAnimation, value: chapters.count)
        .foregroundStyle(.primary)
        .textCase(.none)
        .onChange(of: nextChapter) { _ in
            updateReadButtonText()
        }
        .onChange(of: readingInProgress) { _ in
            updateReadButtonText()
        }
        .onChange(of: allChaptersLocked) { _ in
            updateReadButtonText()
        }
        .onChange(of: allChaptersRead) { _ in
            updateReadButtonText()
        }
        .onChange(of: source != nil) { _ in
            updateReadButtonText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateTrackers)) { _ in
            isTracking = TrackerManager.shared.isTracking(mangaId: manga.identifier)
        }
        .task {
            updateReadButtonText()
        }
        .task(id: manga.identifier) {
            let identifier = manga.identifier
            hasCustomThemeColor = CoverPalette.customColor(for: identifier) != nil
            let edited = await CoreDataManager.shared.container.performBackgroundTask { [identifier] context in
                CoreDataManager.shared.hasEditedKey(
                    mangaId: identifier,
                    key: .cover,
                    context: context
                )
            }
            guard manga.identifier == identifier else { return }
            hasEditedCover = edited
            checkedCoverIdentifier = identifier
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $uploadedCover)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showAlternateCoverPicker) {
            if let source {
                AlternateCoverPicker(source: source, manga: manga) { cover in
                    Task {
                        await CoreDataManager.shared.setCover(
                            mangaId: manga.identifier,
                            coverUrl: cover
                        )
                        setCover(url: cover)
                    }
                }
            }
        }
        .sheet(item: $themeColorSheet) { _ in
            ThemeColorEditor(
                source: source,
                coverURL: manga.cover,
                initialColor: CoverPalette.customColor(for: manga.identifier)
                    ?? CoverPalette.color(for: manga.cover ?? "", identifier: manga.identifier)
                    ?? nsfwBaseColor ?? .gray
            ) { color in
                CoverPalette.setCustomColor(color, for: manga.identifier)
                hasCustomThemeColor = true
            }
        }
        .onChange(of: uploadedCover) { newImage in
            guard let newImage else { return }
            Task {
                if let newURL = await MangaManager.shared.setCover(manga: manga, cover: newImage) {
                    setCover(url: newURL)
                }
            }
        }
    }

    private var coverView: some View {
        MangaCoverView(
            source: source,
            coverImage: manga.cover ?? "",
            paletteIdentifier: manga.identifier,
            width: coverSize.width,
            height: coverSize.height,
            coverDownsampleSide: 630,
            borderColor: Color.white.opacity(0.24),
            privacyPlaceholder: developerMode.value,
            usesHiddenCoverColorPlaceholder: true,
            showsCachedCoverImmediately: true,
            paletteSamplingPriority: .infoView,
            hideNSFW: hidesNSFWCover,
            nsfwBaseColor: nsfwBaseColor,
            onDominantColorChange: onCoverDominantColorChange,
            onImageSizeChange: { size in
                guard size.width > 0, size.height > 0 else { return }
                let ratio = size.width / size.height
                guard ratio != coverAspectRatio else { return }
                withAnimation(loadingAnimation) {
                    coverAspectRatio = ratio
                }
            }
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            coverActions
        } preview: {
            MangaCoverView(
                source: source,
                coverImage: manga.cover ?? "",
                paletteIdentifier: manga.identifier,
                width: coverSize.width,
                height: coverSize.height,
                coverDownsampleSide: 630,
                borderColor: Color.white.opacity(0.24),
                privacyPlaceholder: developerMode.value,
                usesHiddenCoverColorPlaceholder: true,
                showsCachedCoverImmediately: true,
                paletteSamplingPriority: .infoView,
                hideNSFW: hidesNSFWCover,
                nsfwBaseColor: nsfwBaseColor
            )
        }
        .id(manga.cover ?? "")
        .onChange(of: manga.cover) { _ in
            withAnimation(loadingAnimation) {
                coverAspectRatio = 2 / 3
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 23)
        .frame(maxWidth: .infinity)
    }

    private var heroView: some View {
        VStack(spacing: 0) {
            Button {
                onTitlePressed?()
            } label: {
                Text(displayedTitle)
                    .font(.system(size: 22, weight: .heavy))
                    .lineLimit(4)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .contentTransition(isEnteringTransition ? .identity : .interpolate)
                    .animation(isEnteringTransition ? nil : loadingAnimation, value: displayedTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .transaction {
                if descriptionExpansionAnimating || isEnteringTransition {
                    $0.animation = nil
                }
            }

            if let authors = manga.authors, !authors.isEmpty {
                let displayedAuthor = developerMode.value
                    ? DeveloperMode.author(for: String(describing: manga.identifier))
                    : authors.joined(separator: ", ")
                let authorText = Text(displayedAuthor)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(headerTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .contentTransition(isEnteringTransition ? .identity : .interpolate)
                    .animation(isEnteringTransition ? nil : loadingAnimation, value: displayedAuthor)

                Group {
                    if let source, source.supportsAuthorSearch {
                        Button {
                            guard let author = authors.first else { return }
                            let viewController = MangaListViewController(source: source, title: author)
                            viewController.getEntries = { page in
                                try await source.getSearchMangaList(query: nil, page: page, filters: [
                                    .text(id: "author", value: author)
                                ])
                            }
                            path.push(viewController)
                        } label: {
                            HStack(spacing: 5) {
                                Spacer(minLength: 0)
                                authorText
                                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(headerTextColor.opacity(0.55))
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    } else {
                        authorText
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 7)
                .transition(isEnteringTransition ? .identity : .opacity)
                .transaction {
                    if descriptionExpansionAnimating || isEnteringTransition {
                        $0.animation = nil
                    }
                }
            }

            if !metadataText.isEmpty {
                Text(metadataText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(headerTextColor.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .contentTransition(isEnteringTransition ? .identity : .interpolate)
                    .animation(isEnteringTransition ? nil : loadingAnimation, value: metadataText)
                    .transaction {
                        if descriptionExpansionAnimating || isEnteringTransition {
                            $0.animation = nil
                        }
                    }
                    .padding(.top, 7)
                    .padding(.horizontal, 20)
                    .transition(isEnteringTransition ? .identity : .opacity)
                    .transaction {
                        if descriptionExpansionAnimating || isEnteringTransition {
                            $0.animation = nil
                        }
                    }
            }

            HStack(spacing: 12) {
                Button {
                    if let sourcePageURL = manga.url {
                        if let scheme = sourcePageURL.scheme?.lowercased(),
                           scheme == "http" || scheme == "https" {
                            path.present(SFSafariViewController(url: sourcePageURL))
                        } else {
                            openURL(sourcePageURL)
                        }
                    }
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(headerTextColor.opacity(manga.url == nil ? 0.45 : 1))
                .background(headerControlBackgroundColor, in: Circle())
                .overlay(Circle().strokeBorder(controlOutlineColor, lineWidth: 1 / max(displayScale, 1)))
                .disabled(manga.url == nil)
                .accessibilityLabel(NSLocalizedString("OPEN_SOURCE_PAGE"))
                .transaction {
                    if descriptionExpansionAnimating || isEnteringTransition {
                        $0.animation = nil
                    }
                }

                Button {
                    onReadButtonPressed?()
                } label: {
                    VStack(spacing: 0) {
                        Text(readButtonTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .contentTransition(isEnteringTransition ? .identity : .interpolate)
                            .animation(isEnteringTransition ? nil : loadingAnimation, value: readButtonTitle)
                        if let readButtonSubtitle {
                            Text(developerMode.value
                                ? DeveloperMode.chapterTitle(for: String(describing: manga.identifier))
                                : readButtonSubtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(readButtonTextColor.opacity(0.62))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .contentTransition(isEnteringTransition ? .identity : .interpolate)
                                .animation(isEnteringTransition ? nil : loadingAnimation, value: readButtonSubtitle)
                                .transition(.identity)
                        }
                    }
                    .padding(.horizontal, readButtonSubtitle == nil ? 18 : 24)
                    .frame(minWidth: 168, minHeight: 48)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(readButtonTextColor.opacity(readButtonDisabled ? 0.78 : 1))
                .background(readButtonColor.opacity(readButtonDisabled ? 0.67 : 1), in: Capsule())
                .disabled(readButtonDisabled)
                .transaction {
                    if descriptionExpansionAnimating || isEnteringTransition {
                        $0.animation = nil
                    }
                }

                Button {
                    if bookmarked && isTracking {
                        showLibraryRemoveConfirm = true
                    } else {
                        Task {
                            await toggleBookmarked()
                        }
                    }
                } label: {
                    Image(systemName: bookmarked ? "checkmark" : "plus")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(headerTextColor)
                .background(headerControlBackgroundColor, in: Circle())
                .overlay(Circle().strokeBorder(controlOutlineColor, lineWidth: 1 / max(displayScale, 1)))
                .accessibilityLabel(bookmarked ? NSLocalizedString("REMOVE_FROM_LIBRARY") : NSLocalizedString("ADD_TO_LIBRARY"))
                .transaction {
                    if descriptionExpansionAnimating || isEnteringTransition {
                        $0.animation = nil
                    }
                }
                .alert(NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM"), isPresented: $showLibraryRemoveConfirm) {
                    Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                    Button(NSLocalizedString("REMOVE"), role: .destructive) {
                        guard bookmarked else { return }
                        Task {
                            await toggleBookmarked()
                        }
                    }
                } message: {
                    Text(NSLocalizedString("REMOVE_FROM_LIBRARY_CONFIRM_TEXT"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 28)
            .padding(.horizontal, 20)
            .animation(
                descriptionExpansionAnimating || isEnteringTransition ? nil : loadingAnimation,
                value: readButtonTitle
            )
            .animation(
                descriptionExpansionAnimating || isEnteringTransition ? nil : loadingAnimation,
                value: readButtonSubtitle
            )

            if let description = manga.description, !description.isEmpty {
                ExpandableTextView(
                    text: developerMode.value
                        ? DeveloperMode.description(for: String(describing: manga.identifier))
                        : description,
                    textColor: headerTextColor.opacity(0.72),
                    moreTextColor: headerTextColor,
                    onExpansionAnimationChange: { descriptionExpansionAnimating = $0 }
                )
                    .padding(.top, 18)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }

            tagsView
        }
        .foregroundStyle(headerTextColor)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.frame(in: .global).maxY
        } action: { bottom in
            onHeroBottomChange?(bottom)
        }
    }

    @ViewBuilder
    private var coverActions: some View {
        if bookmarked || manga.isLocal() {
            Button {
                showImagePicker = true
            } label: {
                Label(NSLocalizedString("SET_CUSTOM_COVER"), systemImage: "photo.badge.plus")
            }
        }

        if source != nil && checkedCoverIdentifier == manga.identifier && !hasEditedCover && !manga.isLocal() {
            Button {
                Task { await refreshCoverFromSource() }
            } label: {
                Label(NSLocalizedString("REFRESH_COVER"), systemImage: "arrow.clockwise")
            }
        }

        if source != nil && hasEditedCover && !manga.isLocal() {
            Button {
                Task {
                    if let newURL = await MangaManager.shared.resetCover(manga: manga) {
                        setCover(url: newURL, original: true)
                    }
                }
            } label: {
                Label(NSLocalizedString("RESET_COVER"), systemImage: "arrow.uturn.backward")
            }
        }

        if let source, source.features.providesAlternateCovers {
            Button {
                showAlternateCoverPicker = true
            } label: {
                Label(
                    NSLocalizedString("CHOOSE_ALTERNATE_COVER", value: "Choose Alternate Cover", comment: "Choose a source-provided manga cover"),
                    systemImage: "rectangle.stack"
                )
            }
        }

        if let cover = manga.cover, let url = URL(string: cover) {
            Button {
                saveCoverToPhotos(url: url)
            } label: {
                Label(NSLocalizedString("SAVE_TO_PHOTOS"), systemImage: "photo")
            }
        }

        Divider()

        Button {
            themeColorSheet = .cover
        } label: {
            Label(NSLocalizedString("SET_THEME_COLOR"), systemImage: "paintpalette")
        }
        if hasCustomThemeColor {
            Button {
                CoverPalette.setCustomColor(nil, for: manga.identifier)
                hasCustomThemeColor = false
            } label: {
                Label(NSLocalizedString("RESET_THEME_COLOR"), systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var metadataText: String {
        if developerMode.value {
            let count = manga.chapters?.count ?? chapters.count
            return "Ongoing · \(count) \(count == 1 ? "Book" : "Books") · Library"
        }
        var details: [String] = []
        if manga.status != .unknown {
            details.append(manga.status.title)
        }
        if manga.contentRating != .unknown && manga.contentRating != .safe {
            details.append(manga.contentRating.title)
        }
        if let chapterCount = manga.chapters?.count {
            details.append(chapterCount == 1
                ? NSLocalizedString("1_CHAPTER")
                : String(format: NSLocalizedString("%i_CHAPTERS"), chapterCount))
        }
        if let source {
            details.append(source.name)
        }
        return details.joined(separator: " · ")
    }

    @ViewBuilder
    var tagsView: some View {
        let tags = visibleTags
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tags, id: \.self) { tag in
                        let label = TagView(
                            text: developerMode.value ? DeveloperMode.tag(for: tag) : tag,
                            foregroundColor: headerTextColor,
                            backgroundColor: headerControlBackgroundColor,
                            outlineColor: controlOutlineColor
                        )
                        if let source, let filter = source.matchingGenreFilter(for: tag) {
                            Button {
                                let viewController = MangaListViewController(source: source, title: tag)
                                viewController.getEntries = { page in
                                    try await source.getSearchMangaList(query: nil, page: page, filters: [
                                        filter
                                    ])
                                }
                                path.push(viewController)
                            } label: {
                                label
                            }
                        } else {
                            label
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    private var visibleTags: [String] {
        guard let allLabels = manga.tags?.filter({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), !allLabels.isEmpty else { return [] }

        let sourceKey = manga.sourceKey
        let genres: [String]
        let tags: [String]
        if sourceKey.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
            genres = KomgaGenreStore.genres(sourceKey: sourceKey, mangaKey: manga.key)
            tags = Array(allLabels.dropFirst(min(genres.count, allLabels.count)))
        } else if sourceKey.hasPrefix(KavitaSourceRunner.sourceKeyPrefix) {
            genres = KavitaGenreStore.genres(sourceKey: sourceKey, mangaKey: manga.key)
            tags = Array(allLabels.dropFirst(min(genres.count, allLabels.count)))
        } else {
            // Sources with only one label list expose those labels as genres.
            genres = allLabels
            tags = []
        }

        let configuration = LibraryGenreFilterSettings.load()
        let genreIdentifiers = Set(genres.map(LibraryGenreFilterSettings.normalize))
        var displayedIdentifiers: Set<String> = []
        var visibleGenres: [String] = []
        var visibleTags: [String] = []

        if showGenres.value {
            for genre in genres {
                let root = LibraryGenreFilterSettings.rootIdentifier(
                    for: genre,
                    configuration: configuration
                )
                if limitGenresToEnabled.value,
                   !LibraryGenreFilterSettings.isEnabled(genre, configuration: configuration) {
                    continue
                }
                let identifier = limitGenresToEnabled.value
                    ? root
                    : LibraryGenreFilterSettings.normalize(genre)
                guard displayedIdentifiers.insert(identifier).inserted else { continue }
                let label = limitGenresToEnabled.value
                    ? LibraryGenreFilterSettings.displayName(for: root, availableNames: genres)
                    : genre
                visibleGenres.append(label)
            }
        }

        if showTags.value {
            for tag in tags {
                let identifier = LibraryGenreFilterSettings.normalize(tag)
                // A duplicate always uses its genre representation, even when
                // the genre pill itself is hidden by the display settings.
                guard !genreIdentifiers.contains(identifier),
                      displayedIdentifiers.insert(identifier).inserted else { continue }
                visibleTags.append(tag)
            }
        }

        let alphabetical: (String, String) -> Bool = {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return visibleGenres.sorted(by: alphabetical) + visibleTags.sorted(by: alphabetical)
    }

    func toggleBookmarked() async {
        let mangaId = manga.identifier
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(
                mangaId: mangaId,
                context: context
            )
        }
        if inLibrary {
            // remove from library
            await MangaManager.shared.removeFromLibrary(mangaId: mangaId)
            bookmarked = false
        } else {
            if await MangaManager.shouldAskForCategories() { // open category select view
                let viewController = UINavigationController(rootViewController: CategorySelectViewController(manga: manga))
                path.present(viewController)
            } else { // add to library
                bookmarked = true
                await MangaManager.shared.addToLibrary(
                    manga: manga,
                    chapters: manga.chapters ?? []
                )
            }
        }
    }

    private func saveCoverToPhotos(url: URL) {
        guard let viewController = UIApplication.shared.firstKeyWindow?.rootViewController else { return }
        Task {
            do {
                let image = try await ImagePipeline.shared.image(for: url)
                image.saveToAlbum(viewController: viewController)
            } catch {
                LogManager.logger.error("Error loading cover image: \(error)")
            }
        }
    }

    private func setCover(url: String, original: Bool = false) {
        if let oldURL = manga.cover { CoverPalette.forgetMemory(for: oldURL) }
        CoverPalette.invalidate(manga.identifier)
        if manga.cover == url {
            if var components = URLComponents(string: url) {
                var queryItems = components.queryItems ?? []
                queryItems.append(URLQueryItem(name: "edited", value: String(Date().timeIntervalSince1970)))
                components.queryItems = queryItems
                manga.cover = components.string ?? url
            } else {
                manga.cover = url + "?edited=\(Date().timeIntervalSince1970)"
            }
        } else {
            manga.cover = url
        }
        hasEditedCover = !original
        checkedCoverIdentifier = manga.identifier
        NotificationCenter.default.post(name: .updateMangaDetails, object: manga)
    }

    private func refreshCoverFromSource() async {
        guard source != nil, checkedCoverIdentifier == manga.identifier,
              !hasEditedCover, !manga.isLocal() else { return }
        let currentManga = manga
        guard let refreshedCover = await MangaManager.shared.resetCover(manga: currentManga),
              manga.identifier == currentManga.identifier, !hasEditedCover else { return }

        for cover in Set([currentManga.cover, refreshedCover].compactMap { $0 }) {
            if let url = URL(string: cover) {
                await LibraryPagePreviewCache.shared.invalidateCoverCache(
                    for: url,
                    sourceKey: currentManga.sourceKey
                )
            }
        }
        setCover(url: refreshedCover, original: true)
        NotificationCenter.default.post(name: .updateLibrary, object: currentManga.identifier)
    }

    func updateReadButtonText() {
        var title = ""
        var subtitle: String?
        var disabled = true
        if allChaptersLocked {
            title = NSLocalizedString("ALL_CHAPTERS_LOCKED")
        } else if allChaptersRead {
            title = NSLocalizedString("ALL_CHAPTERS_READ")
        } else if source == nil {
            title = NSLocalizedString("UNAVAILABLE")
        } else if let chapter = nextChapter {
            title = readingInProgress
                ? NSLocalizedString("CONTINUE_READING")
                : NSLocalizedString("START_READING")
            subtitle = chapter.sourceDisplayTitle
            disabled = false
        } else {
            title = NSLocalizedString("NO_CHAPTERS_AVAILABLE")
        }
        guard title != readButtonTitle || subtitle != readButtonSubtitle || disabled != readButtonDisabled else { return }
        withAnimation(loadingAnimation) {
            readButtonTitle = title
            readButtonSubtitle = subtitle
            readButtonDisabled = disabled
        }
    }
}

private enum ThemeColorSheetMode: String, Identifiable {
    case cover

    var id: String { rawValue }
}

private struct ThemeColorEditor: View {
    @Environment(\.dismiss) private var dismiss

    let source: AidokuRunner.Source?
    let coverURL: String?
    let onSave: (UIColor) -> Void

    @State private var hex: String
    @State private var wheelColor: Color
    @State private var coverImage: UIImage?
    @State private var coverLoadFailed = false
    @State private var selection: UnitPoint?
    @State private var suggestions: [UIColor] = []
    @State private var lensImage: UIImage?
    @State private var touchLocation: CGPoint?
    @State private var isSampling = false

    init(source: AidokuRunner.Source?, coverURL: String?,
         initialColor: UIColor, onSave: @escaping (UIColor) -> Void) {
        self.source = source
        self.coverURL = coverURL
        self.onSave = onSave
        self._hex = State(initialValue: CoverPalette.hexString(for: initialColor) ?? "#808080")
        self._wheelColor = State(initialValue: Color(uiColor: initialColor))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let coverImage {
                    GeometryReader { geometry in
                        ThemeCoverCanvasView(image: coverImage, selection: $selection) { point, location, active in
                            isSampling = active
                            guard active else { return }
                            let coverOrigin = geometry.frame(in: .global).origin
                            touchLocation = CGPoint(x: coverOrigin.x + location.x, y: coverOrigin.y + location.y)
                            lensImage = magnifiedPatch(from: coverImage, at: point)
                            if let color = sampleColor(from: coverImage, at: point),
                               let value = CoverPalette.hexString(for: color) {
                                hex = value
                                wheelColor = Color(uiColor: color)
                            }
                        }
                    }
                } else if coverLoadFailed {
                    ContentUnavailableView("Cover Unavailable", systemImage: "photo")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("Loading cover…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(suggestions.indices, id: \.self) { index in
                                let color = suggestions[index]
                                Button {
                                    choose(color)
                                } label: {
                                    Circle()
                                        .fill(Color(uiColor: color))
                                        .frame(width: 34, height: 34)
                                        .overlay {
                                            Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 1)
                                        }
                                        .overlay {
                                            if CoverPalette.hexString(for: color)?.caseInsensitiveCompare(hex) == .orderedSame {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .shadow(color: .black.opacity(0.8), radius: 2)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Suggested color \(index + 1)")
                            }
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.trailing, -20)
                }

                HStack(spacing: 12) {
                    ColorPicker("Color Wheel", selection: $wheelColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 38, height: 38)
                        .accessibilityLabel("Choose a color")
                    Text("HEX")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("#RRGGBB", text: $hex)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Drag to sample a color. Pinch to zoom; use two fingers to pan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .navigationTitle("Pick Theme Color")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: wheelColor) { color in
                if let value = CoverPalette.hexString(for: UIColor(color)), value != hex {
                    hex = value
                }
            }
            .onChange(of: hex) { value in
                if let color = CoverPalette.color(fromHex: value), Color(uiColor: color) != wheelColor {
                    wheelColor = Color(uiColor: color)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        guard let selectedColor else { return }
                        onSave(selectedColor)
                        dismiss()
                    }
                    .tint(Color(uiColor: .label))
                    .disabled(selectedColor == nil)
                }
            }
            .task(id: coverURL) {
                guard let coverURL, let url = URL(string: coverURL) else {
                    coverLoadFailed = true
                    return
                }
                do {
                    let request: ImageRequest
                    if let fileURL = url.toAidokuFileUrl() {
                        request = ImageRequest(url: fileURL)
                    } else if let source, !url.isFileURL {
                        request = ImageRequest(
                            urlRequest: await source.getModifiedImageRequest(url: url, context: nil),
                            userInfo: [.processesKey: source.features.processesCovers]
                        )
                    } else {
                        request = ImageRequest(url: url)
                    }
                    let image = try await ImagePipeline.shared.image(for: request)
                    coverImage = image
                    suggestions = image.themeColorSuggestions()
                } catch {
                    coverLoadFailed = true
                }
            }
        }
        .interactiveDismissDisabled()
        .overlay {
            GeometryReader { geometry in
                if isSampling, let lensImage, let touchLocation {
                    let origin = geometry.frame(in: .global).origin
                    let localTouch = CGPoint(x: touchLocation.x - origin.x, y: touchLocation.y - origin.y)
                    magnifier(for: lensImage)
                        .position(lensPosition(for: localTouch, in: geometry.size))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var selectedColor: UIColor? { CoverPalette.color(fromHex: hex) }

    private func choose(_ color: UIColor) {
        guard let value = CoverPalette.hexString(for: color) else { return }
        hex = value
        wheelColor = Color(uiColor: color)
    }

    private func magnifier(for image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.none)
            .frame(width: 126, height: 126)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                Canvas { context, size in
                    var grid = Path()
                    let cellSize = size.width / 11
                    for index in 1..<11 {
                        let offset = CGFloat(index) * cellSize
                        grid.move(to: CGPoint(x: offset, y: 0))
                        grid.addLine(to: CGPoint(x: offset, y: size.height))
                        grid.move(to: CGPoint(x: 0, y: offset))
                        grid.addLine(to: CGPoint(x: size.width, y: offset))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.6)), lineWidth: 0.75)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .padding(6)
            .overlay {
                Circle()
                    .strokeBorder(Color(uiColor: selectedColor ?? .gray), lineWidth: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(uiColor: selectedColor ?? .clear))
                    .frame(width: 12, height: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(.white, lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    private func lensPosition(for touch: CGPoint, in size: CGSize) -> CGPoint {
        // Keep the lens above the finger and fully inside the presented sheet.
        // Shift sideways if the sheet's top edge limits the vertical separation.
        let y = min(max(touch.y - 140, 69), max(size.height - 69, 69))
        let needsSideOffset = touch.y - y < 90
        let preferredX = touch.x + (needsSideOffset ? (touch.x < size.width / 2 ? 125 : -125) : 0)
        let x = min(max(preferredX, 69), max(size.width - 69, 69))
        return CGPoint(x: x, y: y)
    }

    private func magnifiedPatch(from image: UIImage, at point: UnitPoint) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 11, height: 11), format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(
                x: 5.5 - point.x * image.size.width,
                y: 5.5 - point.y * image.size.height,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }

    private func sampleColor(from image: UIImage, at point: UnitPoint) -> UIColor? {
        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let sampleX = min(max(point.x * image.size.width, 0.5), image.size.width - 0.5)
        let sampleY = min(max(point.y * image.size.height, 0.5), image.size.height - 0.5)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            context.interpolationQuality = .none
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0.5 - sampleX, y: 0.5 - sampleY,
                                  width: image.size.width, height: image.size.height))
            UIGraphicsPopContext()
            return UIColor(red: CGFloat(buffer[0]) / 255, green: CGFloat(buffer[1]) / 255,
                           blue: CGFloat(buffer[2]) / 255, alpha: 1)
        }
    }
}

private struct ThemeCoverCanvasView: UIViewRepresentable {
    let image: UIImage
    @Binding var selection: UnitPoint?
    let onSample: (UnitPoint, CGPoint, Bool) -> Void

    func makeUIView(context: Context) -> ThemeCoverCanvas {
        ThemeCoverCanvas(image: image)
    }

    func updateUIView(_ view: ThemeCoverCanvas, context: Context) {
        view.onSample = onSample
        view.setSelection(selection)
    }
}

private final class ThemeCoverCanvas: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    let imageView = UIImageView()
    let borderView = UIView()
    let marker = UIView(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
    var onSample: ((UnitPoint, CGPoint, Bool) -> Void)?
    private var lastViewportSize: CGSize = .zero
    private let image: UIImage

    init(image: UIImage) {
        self.image = image
        super.init(frame: .zero)
        clipsToBounds = true
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 8
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.layer.cornerRadius = 16
        scrollView.layer.cornerCurve = .continuous
        scrollView.clipsToBounds = true
        addSubview(scrollView)

        imageView.image = image
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        borderView.isUserInteractionEnabled = false
        borderView.backgroundColor = .clear
        borderView.layer.cornerRadius = 16
        borderView.layer.cornerCurve = .continuous
        borderView.layer.borderWidth = 1 / UIScreen.main.scale
        borderView.layer.borderColor = UIColor.separator.withAlphaComponent(0.55).cgColor
        addSubview(borderView)

        marker.layer.cornerRadius = 11
        marker.layer.borderWidth = 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        marker.layer.shadowColor = UIColor.black.cgColor
        marker.layer.shadowOpacity = 0.6
        marker.layer.shadowRadius = 3
        marker.layer.shadowOffset = .zero
        marker.isUserInteractionEnabled = false
        marker.isHidden = true
        imageView.addSubview(marker)

        let sampleGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleSample(_:)))
        sampleGesture.minimumPressDuration = 0
        sampleGesture.allowableMovement = .greatestFiniteMagnitude
        sampleGesture.cancelsTouchesInView = false
        sampleGesture.delegate = self
        imageView.addGestureRecognizer(sampleGesture)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastViewportSize,
              image.size.width > 0, image.size.height > 0 else { return }
        lastViewportSize = bounds.size
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let coverSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let coverFrame = CGRect(
            x: (bounds.width - coverSize.width) / 2,
            y: (bounds.height - coverSize.height) / 2,
            width: coverSize.width,
            height: coverSize.height
        )
        scrollView.frame = coverFrame
        borderView.frame = coverFrame
        imageView.frame = CGRect(origin: .zero, size: coverSize)
        scrollView.zoomScale = 1
        scrollView.contentSize = imageView.bounds.size
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    private func centerImage() {
        let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func setSelection(_ selection: UnitPoint?) {
        guard let selection else {
            marker.isHidden = true
            return
        }
        marker.isHidden = false
        marker.center = CGPoint(x: selection.x * imageView.bounds.width, y: selection.y * imageView.bounds.height)
    }

    @objc private func handleSample(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: imageView)
        guard imageView.bounds.width > 0, imageView.bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }
        // The exact outer boundary sits between image pixels. Keep the selected
        // point at the center of the first or last pixel, never on that boundary.
        let xInset = min(0.5 / image.size.width, 0.5)
        let yInset = min(0.5 / image.size.height, 0.5)
        let normalized = UnitPoint(
            x: min(max(point.x / imageView.bounds.width, xInset), 1 - xInset),
            y: min(max(point.y / imageView.bounds.height, yInset), 1 - yInset)
        )
        let x = normalized.x * imageView.bounds.width
        let y = normalized.y * imageView.bounds.height
        let location = imageView.convert(CGPoint(x: x, y: y), to: self)
        let active = gesture.state == .began || gesture.state == .changed
        onSample?(normalized, location, active)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer === scrollView.pinchGestureRecognizer
            || otherGestureRecognizer === scrollView.panGestureRecognizer
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard otherGestureRecognizer is UIPanGestureRecognizer,
              otherGestureRecognizer !== scrollView.panGestureRecognizer,
              let otherView = otherGestureRecognizer.view else { return false }
        // A sheet's pan recognizer lives above this canvas. Let sampling win
        // touches on the image without affecting two-finger image navigation.
        return isDescendant(of: otherView)
    }
}

private struct ThemeSuggestionBucket {
    var count = 0
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var saturation = 0.0

    mutating func add(red: Double, green: Double, blue: Double, saturation: Double) {
        count += 1
        self.red += red
        self.green += green
        self.blue += blue
        self.saturation += saturation
    }

    var color: UIColor {
        UIColor(red: red / Double(count), green: green / Double(count), blue: blue / Double(count), alpha: 1)
    }

    var score: Double {
        pow(Double(count), 0.84) * (0.5 + 0.9 * saturation / Double(count))
    }

    var isNeutral: Bool { saturation / Double(count) < 0.16 }
}

private extension UIImage {
    func themeColorSuggestions(limit: Int = 24) -> [UIColor] {
        guard let cgImage, cgImage.width > 0, cgImage.height > 0 else { return [] }
        let scale = min(96.0 / CGFloat(cgImage.width), 96.0 / CGFloat(cgImage.height))
        let width = max(1, Int((CGFloat(cgImage.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(cgImage.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return [] }

        var buckets: [Int: ThemeSuggestionBucket] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.2 else { continue }
            let red = min(Double(pixels[offset]) / (255 * alpha), 1)
            let green = min(Double(pixels[offset + 1]) / (255 * alpha), 1)
            let blue = min(Double(pixels[offset + 2]) / (255 * alpha), 1)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var opacity: CGFloat = 0
            UIColor(red: red, green: green, blue: blue, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)
            let hueBin = saturation < 0.12 ? 0 : min(23, Int(hue * 24)) + 1
            let saturationBin = min(3, Int(saturation * 4))
            let brightnessBin = min(3, Int(brightness * 4))
            let key = hueBin * 16 + saturationBin * 4 + brightnessBin
            buckets[key, default: ThemeSuggestionBucket()].add(
                red: red, green: green, blue: blue, saturation: Double(saturation)
            )
        }

        var suggestions = dominantColor().map { [$0] } ?? []
        var candidates = buckets.values.sorted { $0.score > $1.score }
        var neutralCount = suggestions.filter { $0.themeSaturation < 0.16 }.count
        while suggestions.count < limit && !candidates.isEmpty {
            let ranked = candidates.enumerated().compactMap { index, bucket -> (index: Int, score: Double, distance: Double)? in
                guard !bucket.isNeutral || neutralCount < 2 else { return nil }
                let color = bucket.color
                let distance = suggestions.map { colorDistance(color, $0) }.min() ?? 1
                guard distance > 0.05 else { return nil }
                return (index, bucket.score * (0.4 + min(distance, 0.8)), distance)
            }
            // Lead with useful, clearly different colors; offer subtle shade
            // variations once those choices are represented.
            let distinct = suggestions.count < 12 ? ranked.filter { $0.distance > 0.09 } : []
            let options = distinct.isEmpty ? ranked : distinct
            guard let best = options.max(by: { $0.score < $1.score }) else { break }
            let choice = candidates.remove(at: best.index)
            suggestions.append(choice.color)
            if choice.isNeutral { neutralCount += 1 }
        }
        return suggestions
    }
}

private extension UIColor {
    var themeSaturation: Double {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Double(saturation)
    }
}

private func colorDistance(_ lhs: UIColor, _ rhs: UIColor) -> Double {
    var lRed: CGFloat = 0, lGreen: CGFloat = 0, lBlue: CGFloat = 0, lAlpha: CGFloat = 0
    var rRed: CGFloat = 0, rGreen: CGFloat = 0, rBlue: CGFloat = 0, rAlpha: CGFloat = 0
    lhs.getRed(&lRed, green: &lGreen, blue: &lBlue, alpha: &lAlpha)
    rhs.getRed(&rRed, green: &rGreen, blue: &rBlue, alpha: &rAlpha)
    let red = Double(lRed - rRed)
    let green = Double(lGreen - rGreen)
    let blue = Double(lBlue - rBlue)
    return sqrt((red * red + green * green + blue * blue) / 3)
}

struct LabelView: View {
    let text: String
    var background = Color(UIColor.tertiarySystemFill)

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .font(.caption2)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct TagView: View {
    let text: String
    let foregroundColor: Color
    let backgroundColor: Color
    let outlineColor: Color
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(foregroundColor.opacity(0.82))
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .textSelection(.enabled)
            .background(backgroundColor, in: Capsule())
            .overlay(Capsule().strokeBorder(outlineColor, lineWidth: 1 / max(displayScale, 1)))
    }
}

private struct AlternateCoverPicker: View {
    let source: AidokuRunner.Source
    let manga: AidokuRunner.Manga
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var covers: [String] = []
    @State private var error: Error?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ErrorView(
                        error: error,
                        restart: { try await source.restart() },
                        retry: loadCovers
                    )
                } else if loading {
                    ProgressView()
                } else if covers.isEmpty {
                    ContentUnavailableView(
                        NSLocalizedString("NO_ALTERNATE_COVERS", value: "No alternate covers available", comment: "Empty alternate cover picker"),
                        systemImage: "photo"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)], spacing: 16) {
                            ForEach(covers, id: \.self) { cover in
                                Button {
                                    onSelect(cover)
                                    dismiss()
                                } label: {
                                    MangaCoverView(
                                        source: source,
                                        coverImage: cover,
                                        width: 110,
                                        height: 165
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(NSLocalizedString("SET_COVER_IMAGE"))
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(NSLocalizedString("COVER"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("DONE")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await loadCovers() }
    }

    private func loadCovers() async {
        loading = true
        error = nil
        do {
            covers = try await source.getAlternateCovers(manga: manga)
                .unique()
                .filter { $0 != manga.cover }
        } catch {
            self.error = error
        }
        loading = false
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    @Previewable @State var bookmarked = false
    @Previewable @State var chapterSortOption = ChapterSortOption.sourceOrder
    @Previewable @State var chapterSortAscending = false

    @Previewable @State var filters: [ChapterFilterOption] = []
    @Previewable @State var langFilter: String?
    @Previewable @State var scanlatorFilter: [String] = []
    @Previewable @State var chapterTitleDisplayMode = ChapterTitleDisplayMode.default

    MangaDetailsHeaderView(
        source: Binding.constant(AidokuRunner.Source.demo()),
        manga: Binding.constant(AidokuRunner.Manga(
            sourceKey: "",
            key: "",
            title: "Manga",
            authors: ["Author"],
            description: "Description"
        )),
        chapters: Binding.constant([]),
        nextChapter: Binding.constant(nil),
        readingInProgress: Binding.constant(false),
        allChaptersLocked: Binding.constant(false),
        allChaptersRead: Binding.constant(false),
        bookmarked: $bookmarked,
        chapterSortOption: $chapterSortOption,
        chapterSortAscending: $chapterSortAscending,
        filters: $filters,
        langFilter: $langFilter,
        scanlatorFilter: $scanlatorFilter,
        chapterTitleDisplayMode: $chapterTitleDisplayMode
    )
}
