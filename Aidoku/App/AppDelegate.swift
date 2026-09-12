//
//  AppDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import AidokuRunner
import CloudKit
import CoreData
import CoreSpotlight
import Nuke
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
#if CANONICAL_BUILD          // true only for App-Store scheme
    static let canonicalID = "app.aidoku.Aidoku"
#else
    static let canonicalID = Bundle.main.bundleIdentifier ?? ""
#endif

    static let isSideloaded = Bundle.main.bundleIdentifier != canonicalID

    private var networkObserverId: UUID?

    private lazy var loadingAlert: UIAlertController = {
        let loadingAlert = UIAlertController(
            title: nil,
            message: NSLocalizedString("LOADING_ELLIPSIS"),
            preferredStyle: .alert
        )
        progressView.tintColor = loadingAlert.view.tintColor
        loadingAlert.view.addSubview(progressView)
        loadingAlert.view.addSubview(loadingIndicator)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        let progressViewSidePadding: CGFloat
        let progressViewBottomPadding: CGFloat
        let indicatorViewSidePadding: CGFloat
        if #available(iOS 26.0, *) {
            progressViewSidePadding = 32
            progressViewBottomPadding = 16
            indicatorViewSidePadding = 16
        } else {
            progressViewSidePadding = 16
            progressViewBottomPadding = 8
            indicatorViewSidePadding = 10
        }

        NSLayoutConstraint.activate([
            progressView.centerXAnchor.constraint(equalTo: loadingAlert.view.centerXAnchor),
            progressView.bottomAnchor.constraint(equalTo: loadingAlert.view.bottomAnchor, constant: -progressViewBottomPadding),
            progressView.widthAnchor.constraint(equalTo: loadingAlert.view.widthAnchor, constant: -(progressViewSidePadding * 2)),

            loadingIndicator.centerYAnchor.constraint(equalTo: loadingAlert.view.centerYAnchor),
            loadingIndicator.leadingAnchor.constraint(equalTo: loadingAlert.view.leadingAnchor, constant: indicatorViewSidePadding),
            loadingIndicator.widthAnchor.constraint(equalToConstant: 50),
            loadingIndicator.heightAnchor.constraint(equalToConstant: 50)
        ])
        return loadingAlert
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let loadingIndicator = UIActivityIndicatorView(frame: .zero)
        loadingIndicator.style = .medium
        loadingIndicator.tag = 3
        return loadingIndicator
    }()

    private lazy var progressView: UIProgressView = {
        let progressView = UIProgressView(frame: .zero)
        progressView.progress = 0
        return progressView
    }()

    var indicatorProgress: Float {
        get { progressView.progress }
        set { progressView.progress = newValue }
    }

    var navigationController: UINavigationController? {
        (UIApplication.shared.firstKeyWindow?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController
    }

    var visibleViewController: UIViewController? {
        ((UIApplication.shared.firstKeyWindow?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController)?
            .visibleViewController
    }

    var topViewController: UIViewController? {
        if var topController = UIApplication.shared.firstKeyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            return topController
        } else {
            return nil
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UserDefaults.standard.register(
            defaults: [
                "History.lockHistoryTab": false,

                "Reader.readingMode": "auto",
                "Reader.skipDuplicateChapters": true,
                "Reader.markDuplicateChapters": true,
                "Reader.downsampleImages": false,
                "Reader.upscaleImages": false,
                "Reader.upscaleMaxHeight": 2000,
                "Reader.cropBorders": false,
                "Reader.disableQuickActions": false,
                "Reader.disableDoubleTap": false,
                "Reader.liveText": false,
                "Reader.hideBarsOnSwipe": false,
                "Reader.tapZones": "disabled",
                "Reader.invertTapZones": false,
                "Reader.animatePageTransitions": true,
                "Reader.backgroundColor": "black",
                "Reader.pagesToPreload": 2,
                "Reader.pagedPageLayout": "auto",
                "Reader.pagedPageOffset": false,
                "Reader.splitWideImages": false,
                "Reader.reverseSplitOrder": false,
                "Reader.verticalInfiniteScroll": true,
                "Reader.pillarbox": false,
                "Reader.pillarboxAmount": 15,
                "Reader.pillarboxOrientation": "both",
                "Reader.autoScroll": false,
                "Reader.autoScrollSpeed": 5,
                "Reader.orientation": "device",

                "Reader.textReaderStyle": "scroll",
                "Reader.textFontFamily": "System",
                "Reader.textFontSize": 18,
                "Reader.textLineSpacing": 8,
                "Reader.textHorizontalPadding": 24,
                "Reader.textTheme": "default",
                "Reader.textAppearance": "system"
            ]
        )
        // Dynamic was an experimental background mode. Preserve a dark canvas
        // for anyone who selected it after the option was removed.
        if UserDefaults.standard.string(forKey: "Reader.backgroundColor") == "systemBlackWhenHidden" {
            UserDefaults.standard.set("black", forKey: "Reader.backgroundColor")
        }
        AppSettings.registerDefaults()

        // PlayCover fix: eagerly initialize the Core Data stack on the main thread
        // before any background migration task touches it. The `lazy var container`
        // and the singleton's init are not thread-safe; under PlayCover's timing the
        // main thread and a background migration task race to initialize them, and the
        // persistent-history remote-change observer's performAndWait deadlocks the
        // launch (no window ever appears). Forcing first init on the main thread here
        // makes the main thread win the race deterministically.
        _ = CoreDataManager.shared

        // check for icloud availability
        // https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)
        // Do not call this method from your app’s main thread. Because this method might take a nontrivial amount of
        // time to set up iCloud and return the requested URL, you should always call it from a secondary thread.
        Task.detached {
            let isiCloudAvailable = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
            if !isiCloudAvailable {
                LogManager.logger.info("iCloud unavailable")
            }
            AppSettings.flags.isiCloudAvailable.register(isiCloudAvailable)
        }

        DataLoader.sharedUrlCache.diskCapacity = 0

        let pipeline = ImagePipeline(delegate: self) {
            let dataLoader: DataLoader = {
                let config = URLSessionConfiguration.default
                config.urlCache = nil
                return DataLoader(configuration: config)
            }()
            let dataCache = try? DataCache(name: "app.aidoku.Aidoku.datacache") // disk cache
            let imageCache = Nuke.ImageCache() // memory cache
            dataCache?.sizeLimit = 500 * 1024 * 1024
            imageCache.costLimit = 100 * 1024 * 1024
            $0.dataCache = dataCache
            $0.imageCache = imageCache
            $0.dataLoader = dataLoader
            $0.dataCachePolicy = .storeOriginalData
            $0.isStoringPreviewsInMemoryCache = false
        }

        ImagePipeline.shared = pipeline

        performMigration()
        handleChaptersToBeDeleted()

        application.applicationSupportsShakeToEdit = true

        BackupManager.shared.register()
        MangaManager.shared.register()

        ReaderTemporaryPageStore.removeAllSessions()

        Task {
            await SourceManager.shared.start()
            LibrarySpotlightIndexer.indexLibrary()
            Task(priority: .utility) {
                await LibraryPagePreviewCache.shared.prewarmLibrary()
            }
            await BackupManager.shared.scheduleAutoBackup()
            if #available(iOS 18.0, *) {
                DictionaryManager.shared.autoUpdateDictionaries()
            }

            networkObserverId = await Reachability.shared.registerConnectionTypeObserver { connectionType in
                switch connectionType {
                    case .wifi:
                        if AppSettings.downloads.downloadOnlyOnWifi.get() {
                            Task {
                                await DownloadManager.shared.resumeDownloads()
                            }
                        }
                    case .cellular, .none:
                        if AppSettings.downloads.downloadOnlyOnWifi.get() {
                            Task {
                                await DownloadManager.shared.pauseDownloads()
                            }
                        }
                }
            }

            if AppSettings.flags.libraryRefreshInProgress.get() {
                presentAlert(
                    title: NSLocalizedString("LIBRARY_REFRESH_INTERRUPTED"),
                    message: NSLocalizedString("LIBRARY_REFRESH_INTERRUPTED_TEXT"),
                    actions: [
                        .init(title: NSLocalizedString("CANCEL"), style: .cancel) { _ in
                            AppSettings.flags.libraryRefreshInProgress.reset()
                        },
                        .init(title: NSLocalizedString("RESUME"), style: .default) { _ in
                            AppSettings.flags.libraryRefreshInProgress.reset()
                            Task {
                                await MangaManager.shared.refreshLibrary()
                            }
                        }
                    ]
                )
            } else {
                await MangaManager.shared.scheduleLibraryRefresh()
            }
        }

        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotifyNewChaptersToggle(_:)),
            name: Notification.Name(AppSettings.library.notifyNewChapters.key),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indexLibraryForSpotlight),
            name: .updateLibrary,
            object: nil
        )

        return true
    }

    @objc private func indexLibraryForSpotlight() {
        LibrarySpotlightIndexer.indexLibrary()
    }

    func handleSpotlightActivity(_ userActivity: NSUserActivity) {
        guard
            userActivity.activityType == CSSearchableItemActionType,
            let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let (sourceKey, mangaKey) = LibrarySpotlightIndexer.parse(identifier: identifier),
            let tabBarController = UIApplication.shared.firstKeyWindow?.rootViewController as? TabBarController
        else { return }

        Task { @MainActor in
            _ = await tabBarController.openLibraryShortcut(sourceKey: sourceKey, mangaKey: mangaKey)
        }
    }

    @objc private func handleNotifyNewChaptersToggle(_ note: Notification) {
        let enabled = (note.object as? Bool) ?? AppSettings.library.notifyNewChapters.get()
        guard enabled else { return }
        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            if !granted {
                await MainActor.run {
                    AppSettings.library.notifyNewChapters.set(false)
                    NotificationCenter.default.post(
                        name: .init(AppSettings.library.notifyNewChapters.key),
                        object: false
                    )
                }
            }
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func updateHomeScreenQuickActions(for pinnedManga: [MangaInfo], isReadingPin: Bool) {
        let context = CoreDataManager.shared.container.viewContext
        let items = context.performAndWait {
            pinnedManga.prefix(4).map { manga in
                let libraryManga = CoreDataManager.shared.getLibraryManga(mangaId: manga.id, context: context)
                return UIApplicationShortcutItem(
                    type: "open-library-manga",
                    localizedTitle: manga.title ?? NSLocalizedString("UNTITLED"),
                    localizedSubtitle: libraryManga.flatMap {
                        LibraryReadingStatus.homeScreenSubtitle(
                            for: $0,
                            isReadingPin: isReadingPin,
                            context: context
                        )
                    },
                    icon: UIApplicationShortcutIcon(systemImageName: "book"),
                    userInfo: [
                        "sourceKey": manga.id.sourceKey as NSSecureCoding,
                        "mangaKey": manga.id.mangaKey as NSSecureCoding
                    ]
                )
            }
        }
        UIApplication.shared.shortcutItems = Array(items)
    }

    func handleHomeScreenQuickAction(
        _ shortcutItem: UIApplicationShortcutItem,
        completion: @escaping (Bool) -> Void
    ) {
        guard
            shortcutItem.type == "open-library-manga",
            let sourceKey = shortcutItem.userInfo?["sourceKey"] as? String,
            let mangaKey = shortcutItem.userInfo?["mangaKey"] as? String,
            let tabBarController = UIApplication.shared.firstKeyWindow?.rootViewController as? TabBarController
        else {
            completion(false)
            return
        }

        Task { @MainActor in
            let success = await tabBarController.openLibraryShortcut(
                sourceKey: sourceKey,
                mangaKey: mangaKey
            )
            completion(success)
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        LibraryPagePreviewCache.removeSessionFiles()
        guard let networkObserverId else { return }
        Task {
            await Reachability.shared.unregisterConnectionTypeObserver(networkObserverId)
        }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        InterfaceOrientationCoordinator.shared.supportedOrientations
    }
}

extension AppDelegate {
    func performMigration() {
        var settingsVersion = AppSettings.flags.currentVersion.get()
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        if let oldSettingsVersion = UserDefaults.standard.string(forKey: "currentVersion") {
            settingsVersion = settingsVersion ?? oldSettingsVersion
            UserDefaults.standard.removeObject(forKey: "currentVersion")
        }

        guard currentVersion != settingsVersion else {
            return
        }

        LogManager.logger.info("Migrating settings from version \(settingsVersion ?? "none") to \(currentVersion ?? "unknown")")

        // migrate history to 0.6 format
        if settingsVersion == "0.5" {
            Task.detached {
                await self.migrateHistory()
            }
        }

        // migration for 0.8.2
        if SourceManager.oldDirectory.exists {
            Task.detached {
                await self.migrateSources()
            }
        }

        migrateSettings()

        AppSettings.flags.currentVersion.set(currentVersion)
    }

    static nonisolated let legacySettingKeys: Set<String> = [
        "Browse.showNsfwSources",
        "Library.pinManga",
        // this is used for checking old backup settings, which won't restore unprefixed settings
//        "downloadChapterSortAscending",
//        "enabledModelFile",
//        "downloadQueueState",
//        "chaptersToBeDeleted",
        "General.portraitRows",
        "General.landscapeRows"
    ]

    func migrateSettings() {
        // migrate showNsfwSources setting
        if UserDefaults.standard.bool(forKey: "Browse.showNsfwSources") {
            AppSettings.browse.contentRatings.set([.safe, .containsNsfw, .primarilyNsfw])
            UserDefaults.standard.removeObject(forKey: "Browse.showNsfwSources")
        }

        // migrate pin settings
        if UserDefaults.standard.bool(forKey: "Library.pinManga") {
            let newValue = switch UserDefaults.standard.integer(forKey: "Library.pinMangaType") {
                case 0: LibraryViewModel.PinType.unread.rawValue
                case 1: LibraryViewModel.PinType.updatedChapters.rawValue
                default: LibraryViewModel.PinType.none.rawValue
            }
            AppSettings.library.pinTitles.set(newValue)
            UserDefaults.standard.removeObject(forKey: "Library.pinManga")
            UserDefaults.standard.removeObject(forKey: "Library.pinMangaType")
        }

        // migrate unprefixed settings
        if UserDefaults.standard.bool(forKey: "downloadChapterSortAscending") {
            AppSettings.flags.downloadChapterSortAscending.set(true)
            UserDefaults.standard.removeObject(forKey: "downloadChapterSortAscending")
        }
        if let enabledModelFile = UserDefaults.standard.string(forKey: "enabledModelFile") {
            UserDefaults.standard.set(enabledModelFile, forKey: "Data.enabledModelFile")
            UserDefaults.standard.removeObject(forKey: "enabledModelFile")
        }
        if let downloadQueueState = UserDefaults.standard.data(forKey: "downloadQueueState") {
            UserDefaults.standard.set(downloadQueueState, forKey: "Data.downloadQueueState")
            UserDefaults.standard.removeObject(forKey: "downloadQueueState")
        }
        if let chaptersToBeDeleted = UserDefaults.standard.data(forKey: "chaptersToBeDeleted") {
            UserDefaults.standard.set(chaptersToBeDeleted, forKey: "Data.chaptersToBeDeleted")
            UserDefaults.standard.removeObject(forKey: "chaptersToBeDeleted")
        }

        // migrate to layout appearance setting
        let portraitRows = UserDefaults.standard.integer(forKey: "General.portraitRows")
        let landscapeRows = UserDefaults.standard.integer(forKey: "General.landscapeRows")
        let defaultPortraitRows = UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2
        let defaultLandscapeRows = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4
        if portraitRows > 0 && portraitRows != defaultPortraitRows {
            AppSettings.appearance.layout.set(.custom)
            AppSettings.appearance.customPortraitRows.set(portraitRows)
            UserDefaults.standard.removeObject(forKey: "General.portraitRows")
        }
        if landscapeRows > 0 && landscapeRows != defaultLandscapeRows {
            AppSettings.appearance.layout.set(.custom)
            AppSettings.appearance.customLandscapeRows.set(landscapeRows)
            UserDefaults.standard.removeObject(forKey: "General.landscapeRows")
        }
    }

    private func migrateHistory() async {
        showLoadingIndicator(style: .progress)
        try? await Task.sleep(nanoseconds: 500 * 1_000_000)
        await CoreDataManager.shared.migrateChapterHistory(progress: { @Sendable progress in
            Task { @MainActor in
                self.indicatorProgress = progress
            }
        })
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
        await hideLoadingIndicator()
    }

    // migration for 0.8.2
    private func migrateSources() async {
        showLoadingIndicator(style: .indefinite)

        try? await Task.sleep(nanoseconds: 500 * 1_000_000)

        // migrate tracker token settings
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("Token.") {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.set(value, forKey: key.replacingOccurrences(of: "Token.", with: "Tracker."))
        }

        // handle lastUpdatedChapters addition
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let items = CoreDataManager.shared.getLibraryManga(context: context)
            // if lastUpdatedChapters is set to the default value, update default to lastUpdated
            for item in items where item.lastUpdatedChapters.timeIntervalSince1970 == 21600 {
                item.lastUpdatedChapters = item.lastUpdated
            }
        }

        // move all sources in old sources directory to the new one
        FileManager.default.moveFiles(in: SourceManager.oldDirectory, to: SourceManager.directory)
        SourceManager.oldDirectory.removeItem()
        await SourceManager.shared.reloadSources()

        await hideLoadingIndicator()
    }

    // delete chapters queued for deletion in last launch
    func handleChaptersToBeDeleted() {
        guard
            let data = UserDefaults.standard.data(forKey: "Data.chaptersToBeDeleted"),
            let chapterKeys = try? JSONDecoder().decode([ChapterIdentifier].self, from: data)
        else {
            return
        }
        Task {
            await DownloadManager.shared.delete(chapters: chapterKeys.map {
                .init(sourceKey: $0.sourceKey, mangaKey: $0.mangaKey, chapterKey: $0.chapterKey)
            })
            UserDefaults.standard.removeObject(forKey: "Data.chaptersToBeDeleted")
        }
    }

    enum LoadingStyle {
        case indefinite
        case progress
    }

    /// Shows a non-interactive loading indicator.
    func showLoadingIndicator(
        style: LoadingStyle = .indefinite,
        message: String = NSLocalizedString("LOADING_ELLIPSIS"),
        completion: (() -> Void)? = nil
    ) {
        loadingAlert.message = message
        switch style {
            case .indefinite:
                loadingIndicator.startAnimating()
                loadingIndicator.isHidden = false
                progressView.isHidden = true
            case .progress:
                progressView.progress = 0
                loadingIndicator.isHidden = true
                progressView.isHidden = false
        }
        topViewController?.present(loadingAlert, animated: true, completion: completion)
    }

    /// Updates the  progress of a shown loading indicator.
    func updateLoadingIndicator(progress: Float) {
        progressView.progress = progress
    }

    /// Dismisses a shown loading indicator.
    func hideLoadingIndicator(completion: (() -> Void)? = nil) async {
        await withCheckedContinuation { continuation in
            loadingAlert.dismiss(animated: true) {
                self.loadingIndicator.stopAnimating()
                continuation.resume()
            }
        }
    }

    func handleUrl(url: URL) {
        if url.scheme == "aidoku" { // aidoku://
            if url.host == "widget", url.pathComponents.count >= 3 {
                let sourceKey = url.pathComponents[1]
                let mangaKey = url.pathComponents[2]
                if let tabBarController = UIApplication.shared.firstKeyWindow?.rootViewController as? TabBarController {
                    Task { @MainActor in
                        _ = await tabBarController.openLibraryShortcut(sourceKey: sourceKey, mangaKey: mangaKey)
                    }
                }
            } else if url.host == "addSourceList" { // addSourceList?url=
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if
                    let listUrlString = components?.queryItems?.first(where: { $0.name == "url" })?.value,
                    let listUrl = URL(string: listUrlString)
                {
                    Task {
                        let sourceListURLs = await SourceManager.shared.getSourceListURLs()
                        guard !sourceListURLs.contains(listUrl) else { return }
                        let success = await SourceManager.shared.addSourceList(url: listUrl)
                        if success {
                            presentAlert(
                                title: NSLocalizedString("SOURCE_LIST_ADDED"),
                                message: NSLocalizedString("SOURCE_LIST_ADDED_TEXT")
                            )
                        } else {
                            presentAlert(
                                title: NSLocalizedString("SOURCE_LIST_ADD_FAIL"),
                                message: NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT")
                            )
                        }
                    }
                }
            } else if let host = url.host, let source = SourceManager.shared.store.source(for: host) {
                // todo: we should support opening items in library even if the source isn't installed
                Task { @MainActor in
                    // support percent encoding characters like "/" for manga and chapter keys
                    let pathComponents = url.percentEncodedPath
                        .split(separator: "/")
                        .map { String($0).removingPercentEncoding ?? String($0) }

                    if !pathComponents.isEmpty { // /sourceId/mangaId
                        let mangaKey = pathComponents[0].removingPercentEncoding ?? url.pathComponents[1]
                        guard
                            let navigationController,
                            let manga = try? await source.getMangaUpdate(
                                manga: AidokuRunner.Manga(sourceKey: source.id, key: mangaKey, title: ""),
                                needsDetails: true,
                                needsChapters: false
                            )
                        else {
                            return
                        }
                        let chapterKey = pathComponents[safe: 1]?.removingPercentEncoding ?? pathComponents[safe: 1]
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        let action = components?.queryItems?.first(where: { $0.name == "action" })?.value.flatMap(MangaView.OpenAction.init)

                        navigationController.pushViewController(
                            MangaViewController(
                                source: source,
                                manga: manga,
                                parent: navigationController.topViewController,
                                chapterKey: chapterKey, // /sourceId/mangaId/chapterId
                                openAction: action // ?action={read,readNext,readLatest}
                            ),
                            animated: true
                        )
                    } else { // /sourceId
                        let vc: UIViewController = if let legacySource = source.legacySource {
                            SourceViewController(source: legacySource)
                        } else {
                            NewSourceViewController(source: source)
                        }
                        navigationController?.pushViewController(vc, animated: true)
                    }
                }
            } else {
                // check for tracker auth callback
                // this shouldn't really be called since authentication should be performed within the app
                if let tracker = TrackerManager.trackers.first(where: {
                    ($0 as? OAuthTracker)?.callbackHost == url.host
                }) as? OAuthTracker {
                    Task {
                        await tracker.handleAuthenticationCallback(url: url)
                    }
                } else {
                    Task {
                        await handleDeepLink(url: url)
                    }
                }
            }
        } else if url.pathExtension == "aix" {
            Task {
                let result = await SourceManager.shared.importSource(from: url)
                if result == nil {
                    presentAlert(
                        title: NSLocalizedString("IMPORT_FAIL"),
                        message: NSLocalizedString("SOURCE_IMPORT_FAIL_TEXT")
                    )
                }
            }
        } else if url.pathExtension == "json" || url.pathExtension == "aib" {
            Task {
                if await BackupManager.shared.importBackup(from: url) {
                    presentAlert(
                        title: NSLocalizedString("BACKUP_IMPORT_SUCCESS"),
                        message: NSLocalizedString("BACKUP_IMPORT_SUCCESS_TEXT")
                    )
                } else {
                    presentAlert(
                        title: NSLocalizedString("IMPORT_FAIL"),
                        message: NSLocalizedString("BACKUP_IMPORT_FAIL_TEXT")
                    )
                }
            }
        } else if
            SourceManager.shared.store.localSourceInstalled
                && LocalFileManager.allowedFileExtensions.contains(url.pathExtension.lowercased())
        {
            Task {
                let fileInfo = await LocalFileManager.shared.loadImportFileInfo(url: url)
                if let fileInfo {
                    navigationController?.present(
                        UIHostingController(rootView: LocalFileImportView(fileInfo: fileInfo)),
                        animated: true
                    )
                } else {
                    presentAlert(
                        title: NSLocalizedString("IMPORT_FAIL"),
                        message: NSLocalizedString("FILE_IMPORT_FAIL_TEXT")
                    )
                }
            }
        } else {
            Task {
                await handleDeepLink(url: url)
            }
        }
    }

    func handleDeepLink(url: URL) async -> Bool {
        guard
            let navigationController,
            let targetUrl = (url as NSURL).resourceSpecifier
        else { return false }

        let allSources = await SourceManager.shared.getLoadedSources()

        // find source that uses the given url
        var targetSource: AidokuRunner.Source?
        var finalUrl: String?
        for source in allSources {
            for sourceUrl in source.urls {
                if let url = (sourceUrl as NSURL).resourceSpecifier, targetUrl.hasPrefix(url) {
                    targetSource = source
                    finalUrl = "\(URL(string: url)?.scheme ?? "https"):\(targetUrl)"
                    break
                }
            }
            if targetSource != nil { break }
        }

        guard let targetSource, let finalUrl else { return false }

        let task = Task { @MainActor in
            do {
                let link = try await targetSource.handleDeepLink(url: finalUrl)

                if let mangaId = link?.mangaKey {
                    // open manga view and scroll to chapter if given
                    guard let manga = try? await targetSource.getMangaUpdate(
                        manga: AidokuRunner.Manga(
                            sourceKey: targetSource.id,
                            key: mangaId,
                            title: ""
                        ),
                        needsDetails: true,
                        needsChapters: false
                    ) else {
                        return false
                    }

                    navigationController.pushViewController(
                        MangaViewController(
                            source: targetSource,
                            manga: manga,
                            parent: navigationController.topViewController,
                            chapterKey: link?.chapterKey,
                            openAction: .read
                        ),
                        animated: true
                    )

                    return true
                } else if let listing = link?.listing {
                    // open source listing
                    let viewController = SourceListingViewController(source: targetSource, listing: listing)
                    navigationController.pushViewController(viewController, animated: true)

                    return true
                }
            } catch {
                LogManager.logger.error("Failed to handle source deep link: \(error.localizedDescription)")
            }

            return false
        }

        return await task.value
    }

    func handleSourceMigration(source: AidokuRunner.Source) {
        presentAlert(
            title: NSLocalizedString("SOURCE_BREAKING_CHANGE"),
            message: NSLocalizedString("SOURCE_BREAKING_CHANGE_TEXT"),
            actions: [
                .init(title: NSLocalizedString("MIGRATE"), style: .default) { _ in
                    if source.features.handlesMigration {
                        // if the source handles the migration, we can migrate all the db ids
                        self.showLoadingIndicator()
                        Task {
                            let (
                                libraryMangaIds,
                                libraryChaptersIds,
                                historyMangaIds,
                                historyChapterIds,
                            ) = await CoreDataManager.shared.container.performBackgroundTask { context in
                                let historyObjects = CoreDataManager.shared.getHistory(sourceKey: source.id, context: context)
                                return (
                                    CoreDataManager.shared.getLibraryManga(sourceKey: source.id, context: context)
                                        .compactMap { $0.manga?.id },
                                    CoreDataManager.shared.getChapters(sourceKey: source.id, context: context)
                                        .map { ($0.mangaId, $0.id) },
                                    historyObjects.map { $0.mangaId },
                                    historyObjects.map { ($0.mangaId, $0.chapterId) },
                                )
                            }
                            var newMangaIds: [String: String] = [:]
                            var newChapterIds: [String: String] = [:]
                            if source.features.handlesNotifications {
                                try? await source.handleNotification(notification: "system.startMigration")
                            }
                            for oldId in libraryMangaIds {
                                newMangaIds[oldId] = try? await source.handleMigration(kind: .manga, mangaKey: oldId, chapterKey: nil)
                            }
                            for oldId in historyMangaIds where newMangaIds[oldId] == nil  {
                                newMangaIds[oldId] = try? await source.handleMigration(kind: .manga, mangaKey: oldId, chapterKey: nil)
                            }
                            for (mangaId, oldId) in libraryChaptersIds {
                                newChapterIds[oldId] = try? await source.handleMigration(kind: .chapter, mangaKey: mangaId, chapterKey: oldId)
                            }
                            if source.features.handlesNotifications {
                                try? await source.handleNotification(notification: "system.endMigration")
                            }
                            for (mangaId, oldId) in historyChapterIds where newChapterIds[oldId] == nil  {
                                newChapterIds[oldId] = try? await source.handleMigration(kind: .chapter, mangaKey: mangaId, chapterKey: oldId)
                            }
                            await CoreDataManager.shared.container.performBackgroundTask { [newMangaIds, newChapterIds] context in
                                let libraryObjects = CoreDataManager.shared.getLibraryManga(sourceKey: source.id, context: context)
                                let chapterObjects = CoreDataManager.shared.getChapters(sourceKey: source.id, context: context)
                                let historyObjects = CoreDataManager.shared.getHistory(sourceKey: source.id, context: context)
                                for object in libraryObjects {
                                    guard
                                        let oldId = object.manga?.id,
                                        let newId = newMangaIds[oldId]
                                    else { continue }
                                    object.manga?.id = newId
                                }
                                for object in chapterObjects {
                                    object.mangaId = newMangaIds[object.mangaId] ?? object.mangaId
                                    object.id = newChapterIds[object.id] ?? object.id
                                }
                                for object in historyObjects {
                                    object.mangaId = newMangaIds[object.mangaId] ?? object.mangaId
                                    object.chapterId = newChapterIds[object.chapterId] ?? object.chapterId
                                }
                                do {
                                    try context.save()
                                } catch {
                                    LogManager.logger.error("Failed to save id migration: \(error)")
                                }
                            }

                            NotificationCenter.default.post(name: .updateLibrary, object: nil)
                            NotificationCenter.default.post(name: .updateHistory, object: nil)

                            await self.hideLoadingIndicator()
                        }
                    } else {
                        // otherwise, we just show the migration view and let the user do it
                        Task {
                            let sourceManga = await CoreDataManager.shared.container.performBackgroundTask { context in
                                let objects = CoreDataManager.shared.getLibraryManga(sourceKey: source.id, context: context)
                                return objects.compactMap { $0.manga?.toNewManga() }
                            }
                            if !sourceManga.isEmpty {
                                let migrateView = MigrateResultsView(targetSources: [source], selectedSeries: sourceManga, forceMigrate: true)
                                let viewController = SwiftUINavigationViewController(rootView: migrateView, addDismissButton: false)
                                self.topViewController?.present(viewController, animated: true)
                            }
                        }
                    }
                }
            ]
        )
    }

    func presentAlert(
        title: String,
        message: String? = nil,
        actions: [UIAlertAction] = [],
        textFieldHandlers: [((UITextField) -> Void)] = [],
        textFieldDisablesLastActionWhenEmpty: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        for handler in textFieldHandlers {
            alertController.addTextField { textField in
                handler(textField)

                if textFieldDisablesLastActionWhenEmpty && textFieldHandlers.count == 1 {
                    actions.last?.isEnabled = !(textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                    NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: textField, queue: .main) { _ in
                        Task { @MainActor in
                            let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            actions.last?.isEnabled = !text.isEmpty
                        }
                    }
                }
            }
        }

        // if no actions are provided, add a default 'OK' action
        if actions.isEmpty {
            let okAction = UIAlertAction(title: NSLocalizedString("OK"), style: .cancel)
            alertController.addAction(okAction)
        } else {
            for action in actions {
                alertController.addAction(action)
            }
        }

        topViewController?.present(alertController, animated: true, completion: completion)
    }
}

extension AppDelegate: ImagePipeline.Delegate {
    nonisolated func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        if context.request.userInfo[.processesKey] as? Bool == true {
            // when using a page processor, don't decode data as an image since it may be invalid
            ImageDecoders.Empty.init()
        } else {
            pipeline.configuration.makeImageDecoder(context)
        }
    }
}

extension AppDelegate: @MainActor UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if
            let sourceId = userInfo[NotificationManager.sourceIdInfoKey] as? String,
            let mangaId = userInfo[NotificationManager.mangaIdInfoKey] as? String,
            let encodedSource = sourceId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
            let encodedManga = mangaId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "aidoku://\(encodedSource)/\(encodedManga)")
        {
            Task { @MainActor in
                self.handleUrl(url: url)
            }
        }
        completionHandler()
    }
}

private enum LibraryReadingStatus {
    static func homeScreenSubtitle(
        for libraryManga: LibraryMangaObject,
        isReadingPin: Bool,
        context: NSManagedObjectContext
    ) -> String? {
        guard let manga = libraryManga.manga else { return nil }
        let chapters = ((manga.chapters?.allObjects as? [ChapterObject]) ?? [])
            .sorted { $0.sourceOrder < $1.sourceOrder }

        guard isReadingPin else {
            return "\(chapters.count) chapters"
        }

        let identifier = manga.identifier
        let history = CoreDataManager.shared.getHistoryForManga(mangaId: identifier, context: context)
            .sorted { ($0.dateRead ?? .distantPast) > ($1.dateRead ?? .distantPast) }
        guard let latestHistory = history.first else { return "\(chapters.count) chapters" }
        let historyChapter = latestHistory.chapter ?? CoreDataManager.shared.getChapter(
            chapterId: ChapterIdentifier(
                sourceKey: identifier.sourceKey,
                mangaKey: identifier.mangaKey,
                chapterKey: latestHistory.chapterId
            ),
            context: context
        )
        guard let historyChapter else { return "\(chapters.count) chapters" }

        guard let currentIndex = chapters.firstIndex(where: { $0.sourceOrder == historyChapter.sourceOrder }) else {
            return "\(chapters.count) chapters"
        }

        if latestHistory.completed {
            let nextIndex = chapters.index(after: currentIndex)
            guard nextIndex < chapters.endIndex else {
                return manga.status == AidokuRunner.PublishingStatus.completed.rawValue ? "Finished" : "Caught up"
            }
            return chapterSubtitle(for: chapters[nextIndex])
        }

        guard latestHistory.total > 0 else {
            return chapterSubtitle(for: historyChapter)
        }
        return chapterSubtitle(for: historyChapter)
    }

    static func spotlightSubtitle(for libraryManga: LibraryMangaObject) -> String? {
        guard let manga = libraryManga.manga else { return nil }
        let chapterCount = manga.chapters?.count ?? 0
        return "\(chapterCount) chapters"
    }

    private static func chapterSubtitle(for chapter: ChapterObject) -> String {
        let number = chapter.chapter?.stringValue ?? chapter.volume?.stringValue ?? chapter.title ?? "?"
        return "Chapter \(number)"
    }
}

private enum LibrarySpotlightIndexer {
    private static let domainIdentifier = "library"
    private static let identifierPrefix = "library:"
    private static let separator = "\u{1F}"

    private struct ItemMetadata: Sendable {
        let sourceKey: String
        let mangaKey: String
        let title: String
        let author: String?
        let artist: String?
        let readingStatus: String?
        let tags: [String]
        let cover: String?
    }

    static func indexLibrary() {
        Task(priority: .utility) {
            let metadata = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getLibraryManga(context: context).compactMap { object -> ItemMetadata? in
                    guard let manga = object.manga, !manga.title.isEmpty else { return nil }
                    return ItemMetadata(
                        sourceKey: manga.sourceId,
                        mangaKey: manga.id,
                        title: manga.title,
                        author: manga.author,
                        artist: manga.artist,
                        readingStatus: LibraryReadingStatus.spotlightSubtitle(for: object),
                        tags: manga.tags ?? [],
                        cover: manga.cover
                    )
                }
            }

            // Publish the text metadata immediately, then update each result as
            // its cover becomes available through the app's normal image path.
            try? await CSSearchableIndex.default().indexSearchableItems(
                metadata.map { searchableItem(for: $0) }
            )

            for item in metadata {
                guard let cover = item.cover,
                      let thumbnail = await thumbnailData(for: cover, sourceKey: item.sourceKey) else {
                    continue
                }
                try? await CSSearchableIndex.default().indexSearchableItems([
                    searchableItem(for: item, thumbnailData: thumbnail)
                ])
            }
        }
    }

    private static func searchableItem(for item: ItemMetadata, thumbnailData: Data? = nil) -> CSSearchableItem {
        let identifier = makeIdentifier(sourceKey: item.sourceKey, mangaKey: item.mangaKey)
        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        attributes.title = item.title
        attributes.displayName = item.title
        attributes.keywords = [item.title, item.author, item.artist].compactMap { $0 } + item.tags
        // Spotlight shows contentDescription as the result subtitle. Retain
        // artist and author as keywords without presenting them as the subtitle.
        attributes.contentDescription = item.readingStatus
        attributes.thumbnailData = thumbnailData
        return CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }

    private static func thumbnailData(for cover: String, sourceKey: String) async -> Data? {
        guard let url = URL(string: cover) else { return nil }

        let image: UIImage?
        if let fileURL = url.toAidokuFileUrl() {
            image = UIImage(contentsOfFile: fileURL.path)
        } else {
            let source = await SourceManager.shared.source(for: sourceKey)
            let urlRequest = if let source {
                await source.getModifiedImageRequest(url: url, context: nil)
            } else {
                URLRequest(url: url)
            }
            var processors: [ImageProcessing] = []
            if let source, source.features.processesCovers {
                processors.append(CoverInterceptorProcessor(source: source))
            }
            var request = ImageRequest(
                urlRequest: urlRequest,
                processors: processors,
                userInfo: [.processesKey: source?.features.processesCovers ?? false]
            )
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 512)
            image = try? await ImagePipeline.shared.image(for: request)
        }
        guard let image else { return nil }

        let targetSize = CGSize(width: 320, height: 480)
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let thumbnail = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: drawRect)
        }
        return thumbnail.jpegData(compressionQuality: 0.85)
    }

    static func parse(identifier: String) -> (sourceKey: String, mangaKey: String)? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let encoded = String(identifier.dropFirst(identifierPrefix.count))
        guard
            let data = Data(base64Encoded: encoded),
            let value = String(data: data, encoding: .utf8),
            let separatorIndex = value.firstIndex(of: Character(separator))
        else { return nil }

        let sourceKey = String(value[..<separatorIndex])
        let mangaKey = String(value[value.index(after: separatorIndex)...])
        guard !sourceKey.isEmpty, !mangaKey.isEmpty else { return nil }
        return (sourceKey, mangaKey)
    }

private static func makeIdentifier(sourceKey: String, mangaKey: String) -> String {
        let value = "\(sourceKey)\(separator)\(mangaKey)"
        let encoded = Data(value.utf8).base64EncodedString()
        return identifierPrefix + encoded
    }
}

/*
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
        let finalChapter = chapters.max { $0.sourceOrder < $1.sourceOrder }
        let isFinalChapter = currentChapter != nil && currentChapter?.sourceOrder == finalChapter?.sourceOrder

        if latestHistory?.completed == true && isFinalChapter {
            return manga.status == AidokuRunner.PublishingStatus.completed.rawValue ? "Finished" : "Caught Up"
        }

        let volume = currentChapter?.volume?.stringValue
            ?? (latestHistory == nil && currentChapter != nil ? "1" : nil)
        guard let volume else { return currentChapter?.title }

        if (latestHistory?.progress ?? 0) <= 1 {
            return "Start reading volume \(volume)"
        }

        guard let latestHistory, latestHistory.total > 0 else {
            return "Volume \(volume)"
        }
        let percentage = (Double(latestHistory.progress) / Double(latestHistory.total) * 100).rounded()
        return "Volume \(volume), \(min(max(Int(percentage), 0), 100))% read"
    }
}

private enum LibrarySpotlightIndexer {
    private static let domainIdentifier = "library"
    private static let identifierPrefix = "library:"
    private static let separator = "\u{1F}"

    private struct ItemMetadata: Sendable {
        let sourceKey: String
        let mangaKey: String
        let title: String
        let author: String?
        let artist: String?
        let readingStatus: String?
        let tags: [String]
        let cover: String?
    }

    static func indexLibrary() {
        Task(priority: .utility) {
            let metadata = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getLibraryManga(context: context).compactMap { object -> ItemMetadata? in
                    guard let manga = object.manga, !manga.title.isEmpty else { return nil }
                    return ItemMetadata(
                        sourceKey: manga.sourceId,
                        mangaKey: manga.id,
                        title: manga.title,
                        author: manga.author,
                        artist: manga.artist,
                        readingStatus: LibraryReadingStatus.subtitle(for: object, context: context),
                        tags: manga.tags ?? [],
                        cover: manga.cover
                    )
                }
            }

            // Publish the text metadata immediately, then update each result as
            // its cover becomes available through the app's normal image path.
            try? await CSSearchableIndex.default().indexSearchableItems(
                metadata.map { searchableItem(for: $0) }
            )

            for item in metadata {
                guard let cover = item.cover,
                      let thumbnail = await thumbnailData(for: cover, sourceKey: item.sourceKey) else {
                    continue
                }
                try? await CSSearchableIndex.default().indexSearchableItems([
                    searchableItem(for: item, thumbnailData: thumbnail)
                ])
            }
        }
    }

    private static func searchableItem(for item: ItemMetadata, thumbnailData: Data? = nil) -> CSSearchableItem {
        let identifier = makeIdentifier(sourceKey: item.sourceKey, mangaKey: item.mangaKey)
        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        attributes.title = item.title
        attributes.displayName = item.title
        attributes.keywords = [item.title, item.author, item.artist].compactMap { $0 } + item.tags
        // Spotlight shows contentDescription as the result subtitle. Retain
        // artist and author as keywords without presenting them as the subtitle.
        attributes.contentDescription = item.readingStatus
        attributes.thumbnailData = thumbnailData
        return CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }

    private static func thumbnailData(for cover: String, sourceKey: String) async -> Data? {
        guard let url = URL(string: cover) else { return nil }

        let image: UIImage?
        if let fileURL = url.toAidokuFileUrl() {
            image = UIImage(contentsOfFile: fileURL.path)
        } else {
            let source = await SourceManager.shared.source(for: sourceKey)
            let urlRequest = if let source {
                await source.getModifiedImageRequest(url: url, context: nil)
            } else {
                URLRequest(url: url)
            }
            var processors: [ImageProcessing] = []
            if let source, source.features.processesCovers {
                processors.append(CoverInterceptorProcessor(source: source))
            }
            var request = ImageRequest(
                urlRequest: urlRequest,
                processors: processors,
                userInfo: [.processesKey: source?.features.processesCovers ?? false]
            )
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 512)
            image = try? await ImagePipeline.shared.image(for: request)
        }
        guard let image else { return nil }

        let targetSize = CGSize(width: 320, height: 480)
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let thumbnail = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: drawRect)
        }
        return thumbnail.jpegData(compressionQuality: 0.85)
    }

    static func parse(identifier: String) -> (sourceKey: String, mangaKey: String)? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let encoded = String(identifier.dropFirst(identifierPrefix.count))
        guard
            let data = Data(base64Encoded: encoded),
            let value = String(data: data, encoding: .utf8),
            let separatorIndex = value.firstIndex(of: Character(separator))
        else { return nil }

        let sourceKey = String(value[..<separatorIndex])
        let mangaKey = String(value[value.index(after: separatorIndex)...])
        guard !sourceKey.isEmpty, !mangaKey.isEmpty else { return nil }
        return (sourceKey, mangaKey)
    }

    private static func makeIdentifier(sourceKey: String, mangaKey: String) -> String {
        let value = "\(sourceKey)\(separator)\(mangaKey)"
        let encoded = Data(value.utf8).base64EncodedString()
        return identifierPrefix + encoded
    }
}
*/
