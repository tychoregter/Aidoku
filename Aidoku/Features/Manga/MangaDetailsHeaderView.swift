//
//  MangaDetailsHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import Nuke
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

    @State private var readButtonTitle = NSLocalizedString("LOADING_ELLIPSIS")
    @State private var readButtonSubtitle: String?
    @State private var readButtonDisabled = true
    @State private var isTracking = false
    @State private var showLibraryRemoveConfirm = false
    @State private var hasEditedCover = false
    @State private var showImagePicker = false
    @State private var uploadedCover: UIImage?
    @State private var coverAspectRatio: CGFloat = 2 / 3
    @State private var showAlternateCoverPicker = false
    @State private var descriptionExpansionAnimating = false
    @StateObject private var developerMode = UserDefaultsBool(key: AppSettings.general.developerMode.key)
    @StateObject private var hideNSFWCovers = UserDefaultsBool(key: AppSettings.appearance.blurNSFWCovers.key)
    @StateObject private var showGenres = UserDefaultsBool(key: AppSettings.library.showMangaInfoGenres.key)
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
            hasEditedCover = await CoreDataManager.shared.container.performBackgroundTask { [manga] context in
                CoreDataManager.shared.hasEditedKey(
                    mangaId: manga.identifier,
                    key: .cover,
                    context: context
                )
            }
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
            width: coverSize.width,
            height: coverSize.height,
            coverDownsampleSide: 630,
            borderColor: Color.white.opacity(0.24),
            privacyPlaceholder: developerMode.value,
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
                width: coverSize.width,
                height: coverSize.height,
                coverDownsampleSide: 630,
                borderColor: Color.white.opacity(0.24),
                privacyPlaceholder: developerMode.value,
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
                        openURL(sourcePageURL)
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
                    Text(readButtonTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(isEnteringTransition ? .identity : .interpolate)
                        .animation(isEnteringTransition ? nil : loadingAnimation, value: readButtonTitle)
                        .padding(.bottom, readButtonSubtitle == nil ? 0 : 17)
                        .overlay(alignment: .bottom) {
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
                                    .frame(maxWidth: .infinity)
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
                Label(NSLocalizedString("UPLOAD_CUSTOM_COVER"), systemImage: "photo.badge.plus")
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
                            backgroundColor: headerControlBackgroundColor
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
        guard let tags = manga.tags, !tags.isEmpty else { return [] }

        let sourceKey = manga.sourceKey
        let genreCount: Int?
        if sourceKey.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
            genreCount = KomgaGenreStore.genres(sourceKey: sourceKey, mangaKey: manga.key).count
        } else if sourceKey.hasPrefix(KavitaSourceRunner.sourceKeyPrefix) {
            genreCount = KavitaGenreStore.genres(sourceKey: sourceKey, mangaKey: manga.key).count
        } else {
            // Sources with only one label list expose those labels as genres.
            genreCount = nil
        }

        return tags.enumerated().compactMap { index, tag in
            let isGenre = genreCount.map { index < $0 } ?? true
            return (isGenre ? showGenres.value : showTags.value) ? tag : nil
        }
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
        if manga.cover == url {
            manga.cover = url + "?edited=\(Date().timeIntervalSince1970)"
        } else {
            manga.cover = url
        }
        hasEditedCover = !original
        NotificationCenter.default.post(name: .updateMangaDetails, object: manga)
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

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(foregroundColor.opacity(0.82))
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .textSelection(.enabled)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 100))
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
