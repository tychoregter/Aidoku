//
//  TabBarController.swift
//  Aidoku
//
//  Created by Skitty on 7/26/25.
//

import Combine
import AidokuRunner
import SwiftUI

extension UIScrollView {
    /// Invokes the same private UIKit path used by the status-bar scroll-to-top gesture.
    /// Returns false when the selector is unavailable or UIKit declines the scroll.
    @discardableResult
    func performSystemScrollToTop(animated: Bool) -> Bool {
        let selector = NSSelectorFromString("_scrollToTopIfPossible:")
        guard responds(to: selector) else { return false }

        typealias Implementation = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let implementation = unsafeBitCast(method(for: selector), to: Implementation.self)
        return implementation(self, selector, animated)
    }
}

class TabBarController: UITabBarController {
    private var usesLibrarySettingsOverlay: Bool {
        !AppSettings.appearance.dedicatedSettingsTab.get()
    }
    private var hasDedicatedTabs: Bool {
        AppSettings.appearance.dedicatedFavoritesTab.get()
            || AppSettings.appearance.dedicatedBrowseTab.get()
            || AppSettings.appearance.dedicatedHistoryTab.get()
            || AppSettings.appearance.dedicatedSettingsTab.get()
    }
    private var originalFrame: CGRect = .zero
    private var shrunkFrame: CGRect = .zero
    private var cancellables: [AnyCancellable] = []

    private var settingsPath: NavigationCoordinator?
    private var historyPath: NavigationCoordinator?
    private weak var libraryViewController: LibraryViewController?
    private weak var favoritesViewController: LibraryViewController?
    private var previousSelectedIndex: Int?

    private var libraryNavigationController: UINavigationController?
    private var favoritesNavigationController: UINavigationController?
    private var browseNavigationController: UINavigationController?
    private var historyNavigationController: UINavigationController?
    private var searchNavigationController: UINavigationController?
    private var settingsViewController: UIViewController?
    private weak var settingsRootViewController: UIViewController?
    private var cachedModernTabs: [String: AnyObject] = [:]

    private let searchController = SearchViewController()
    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior = .onScrollDown
        }

        let libraryRootViewController = LibraryViewController()
        libraryRootViewController.settingsPresentationHandler = { [weak self] in
            self?.presentSettingsOverlay()
        }
        self.libraryViewController = libraryRootViewController
        let libraryViewController = NavigationController(rootViewController: libraryRootViewController)
        libraryNavigationController = libraryViewController
        let favoritesRootViewController = LibraryViewController(scope: .favorites)
        self.favoritesViewController = favoritesRootViewController
        let favoritesViewController = NavigationController(rootViewController: favoritesRootViewController)
        favoritesNavigationController = favoritesViewController
        let browseViewController = NavigationController(rootViewController: BrowseViewController())
        browseNavigationController = browseViewController
        let searchViewController = NavigationController(rootViewController: searchController)
        searchNavigationController = searchViewController

        let historyPath = NavigationCoordinator(rootViewController: nil)
        let historyHostingController = UIHostingController(
            rootView: HistoryView().environmentObject(historyPath)
        )
        historyPath.rootViewController = historyHostingController
        let historyViewController = NavigationController(rootViewController: historyHostingController)
        self.historyPath = historyPath
        historyNavigationController = historyViewController

        let settingsPath = NavigationCoordinator(rootViewController: nil)
        // Browse, source, and manga-info screens are UIKit controllers.  Keeping
        // Settings in a UIKit navigation controller too gives that route one stack
        // owner; pushing those screens into SwiftUI's NavigationStack allowed iOS
        // to reconcile and remove the source screen on the first return.
        let hosting = UIHostingController(rootView: SettingsView().environmentObject(settingsPath))
        let settingsNavigationController = NavigationController(rootViewController: hosting)
        settingsNavigationController.navigationBar.prefersLargeTitles = true
        settingsPath.rootViewController = settingsNavigationController
        let settingsViewController: UIViewController = settingsNavigationController
        self.settingsPath = settingsPath
        self.settingsViewController = settingsViewController
        settingsRootViewController = hosting
        configureSettingsRootNavigationItem()

        libraryViewController.navigationBar.prefersLargeTitles = true
        browseViewController.navigationBar.prefersLargeTitles = true
        historyViewController.navigationBar.prefersLargeTitles = true
        searchViewController.navigationBar.prefersLargeTitles = true

        configureTabs()

        NotificationCenter.default.publisher(for: .init(AppSettings.general.incognitoMode.key))
            .sink { [weak self] _ in
                self?.updateFrame(animated: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: .init(AppSettings.appearance.dedicatedBrowseTab.key)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.configureTabs()
        }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(
            for: .init(AppSettings.appearance.dedicatedHistoryTab.key)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.configureTabs()
        }
        .store(in: &cancellables)
        NotificationCenter.default.publisher(
            for: .init(AppSettings.appearance.dedicatedFavoritesTab.key)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.configureTabs() }
        .store(in: &cancellables)
        NotificationCenter.default.publisher(
            for: .init(AppSettings.appearance.dedicatedSettingsTab.key)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.settingsTabPreferenceDidChange() }
        .store(in: &cancellables)

    }

    private func configureTabs() {
        guard
            let libraryNavigationController,
            let favoritesNavigationController,
            let browseNavigationController,
            let historyNavigationController,
            let searchNavigationController,
            let settingsViewController
        else { return }

        if #available(iOS 26.0, *) {
            let selectedIdentifier = selectedTab?.identifier
            let libraryTab = modernTab(
                title: NSLocalizedString("LIBRARY"),
                image: UIImage(systemName: "books.vertical.fill"),
                identifier: "library",
                viewController: libraryNavigationController
            )
            libraryTab.allowsHiding = false
            libraryTab.preferredPlacement = .fixed
            var fixedTabs = [libraryTab]
            if AppSettings.appearance.dedicatedFavoritesTab.get() {
                fixedTabs.append(modernTab(
                    title: "Favorites",
                    image: UIImage(systemName: "star.fill"),
                    identifier: "favorites",
                    viewController: favoritesNavigationController
                ))
            }
            if AppSettings.appearance.dedicatedBrowseTab.get() {
                fixedTabs.append(
                    modernTab(
                        title: NSLocalizedString("BROWSE"),
                        image: UIImage(systemName: "globe"),
                        identifier: "browse",
                        viewController: browseNavigationController
                    )
                )
            }
            if AppSettings.appearance.dedicatedHistoryTab.get() {
                fixedTabs.append(
                    modernTab(
                        title: NSLocalizedString("HISTORY"),
                        image: UIImage(systemName: "clock.fill"),
                        identifier: "history",
                        viewController: historyNavigationController
                    )
                )
            }
            if !usesLibrarySettingsOverlay {
                fixedTabs.append(modernTab(
                    title: NSLocalizedString("SETTINGS"),
                    image: UIImage(systemName: "gear"),
                    identifier: "settings",
                    viewController: settingsViewController
                ))
            }
            fixedTabs.dropFirst().forEach {
                $0.allowsHiding = false
                $0.preferredPlacement = .fixed
            }
            let searchTab = modernSearchTab(viewController: searchNavigationController)
            tabs = hasDedicatedTabs ? fixedTabs + [searchTab] : fixedTabs
            selectedTab = tabs.first { $0.identifier == selectedIdentifier ?? "library" }
                ?? fixedTabs.first { $0.identifier == "library" }
        } else {
            let selectedController = selectedViewController
            libraryNavigationController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("LIBRARY"),
                image: UIImage(systemName: "books.vertical.fill"),
                tag: 0
            )
            browseNavigationController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("BROWSE"),
                image: UIImage(systemName: "globe"),
                tag: 1
            )
            historyNavigationController.tabBarItem = UITabBarItem(tabBarSystemItem: .history, tag: 2)
            favoritesNavigationController.tabBarItem = UITabBarItem(
                title: "Favorites", image: UIImage(systemName: "star.fill"), tag: 1
            )
            searchNavigationController.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 3)
            settingsViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("SETTINGS"),
                image: UIImage(systemName: "gear"),
                tag: 4
            )
            var controllers: [UIViewController] = [libraryNavigationController]
            if AppSettings.appearance.dedicatedFavoritesTab.get() { controllers.append(favoritesNavigationController) }
            if AppSettings.appearance.dedicatedBrowseTab.get() { controllers.append(browseNavigationController) }
            if AppSettings.appearance.dedicatedHistoryTab.get() { controllers.append(historyNavigationController) }
            if hasDedicatedTabs {
                controllers.append(searchNavigationController)
            }
            if !usesLibrarySettingsOverlay {
                controllers.append(settingsViewController)
            }
            viewControllers = controllers
            selectedViewController = controllers.contains { $0 === selectedController }
                ? selectedController
                : libraryNavigationController
        }

        tabBar.isHidden = !hasDedicatedTabs

        previousSelectedIndex = selectedIndex
    }

    private func presentSettingsOverlay() {
        guard
            usesLibrarySettingsOverlay,
            let settingsViewController,
            settingsViewController.presentingViewController == nil
        else { return }

        popSettingsToRoot()
        settingsViewController.modalPresentationStyle = .pageSheet
        if let sheet = settingsViewController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        selectedViewController?.present(settingsViewController, animated: true)
    }

    private func settingsTabPreferenceDidChange() {
        configureSettingsRootNavigationItem()

        guard
            !usesLibrarySettingsOverlay,
            let settingsViewController,
            settingsViewController.presentingViewController != nil
        else {
            configureTabs()
            return
        }

        settingsViewController.dismiss(animated: true) { [weak self] in
            self?.configureTabs()
        }
    }

    private func configureSettingsRootNavigationItem() {
        guard let settingsRootViewController else { return }
        settingsRootViewController.navigationItem.largeTitleDisplayMode = usesLibrarySettingsOverlay ? .never : .always
        settingsRootViewController.navigationItem.rightBarButtonItem = usesLibrarySettingsOverlay
            ? UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(dismissSettingsOverlay)
            )
            : nil
    }

    @objc private func dismissSettingsOverlay() {
        settingsViewController?.dismiss(animated: true)
    }

    @MainActor
    func openLibraryShortcut(sourceKey: String, mangaKey: String) async -> Bool {
        guard let libraryNavigationController else { return false }

        if #available(iOS 26.0, *) {
            selectedTab = tabs.first { $0.identifier == "library" }
        } else {
            selectedViewController = libraryNavigationController
        }

        guard
            let source = await SourceManager.shared.source(for: sourceKey),
            let infoManga = try? await source.getMangaUpdate(
                manga: AidokuRunner.Manga(sourceKey: sourceKey, key: mangaKey, title: ""),
                needsDetails: true,
                needsChapters: false
            )
        else {
            return false
        }

        let mangaInfo = MangaInfo(
            id: MangaIdentifier(sourceKey: sourceKey, mangaKey: mangaKey),
            coverUrl: infoManga.cover.flatMap(URL.init(string:)),
            title: infoManga.title,
            author: infoManga.authors?.joined(separator: ", "),
            url: infoManga.url
        )

        if !AppSettings.library.opensReaderView.get() {
            let parent = libraryNavigationController.topViewController
            libraryNavigationController.pushViewController(
                MangaViewController(source: source, manga: infoManga, parent: parent),
                animated: true
            )
            return true
        }

        let (sourceOrderedChapters, nextChapter) = await MangaManager.shared.getNextChapter(mangaId: mangaInfo.id)

        if let nextChapter {
            let manga = AidokuRunner.Manga(
                sourceKey: sourceKey,
                key: mangaKey,
                title: infoManga.title,
                chapters: sourceOrderedChapters
            )
            let readerController = ReaderViewController(
                source: source,
                manga: manga,
                chapter: nextChapter
            )
            let readerNavigationController = ReaderNavigationController(
                readerViewController: readerController,
                mangaInfo: mangaInfo
            )
            if #available(iOS 18.0, *) {
                readerNavigationController.preferredTransition = .zoom { [weak self] _ in
                    self?.libraryViewController?.transitionSourceView(for: mangaInfo.id)
                }
            }
            readerNavigationController.modalPresentationStyle = .fullScreen
            libraryNavigationController.present(readerNavigationController, animated: true)
        } else {
            let parent = libraryNavigationController.topViewController
            libraryNavigationController.pushViewController(
                MangaViewController(source: source, manga: infoManga, parent: parent),
                animated: true
            )
        }
        return true
    }

    @available(iOS 26.0, *)
    private func modernTab(
        title: String,
        image: UIImage?,
        identifier: String,
        viewController: UIViewController
    ) -> UITab {
        if let tab = cachedModernTabs[identifier] as? UITab {
            return tab
        }
        let tab = UITab(title: title, image: image, identifier: identifier) { _ in
            viewController
        }
        cachedModernTabs[identifier] = tab
        return tab
    }

    @available(iOS 26.0, *)
    private func modernSearchTab(viewController: UIViewController) -> UISearchTab {
        if let tab = cachedModernTabs["search"] as? UISearchTab {
            return tab
        }
        let tab = UISearchTab { _ in viewController }
        tab.automaticallyActivatesSearch = true
        cachedModernTabs["search"] = tab
        return tab
    }

    func updateFrame(animated: Bool = false) {
        if originalFrame == .zero {
            let bannerHeight = (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.totalBannerHeight ?? 0
            originalFrame = view.frame
            shrunkFrame = .init(
                x: originalFrame.origin.x,
                y: originalFrame.origin.y + bannerHeight,
                width: originalFrame.width,
                height: originalFrame.height - bannerHeight
            )
        }
        func commit() {
            if AppSettings.general.incognitoMode.get() {
                view.frame = shrunkFrame
            } else {
                view.frame = originalFrame
            }
        }
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                commit()
            }
        } else {
            commit()
        }
    }
}

extension TabBarController {
    func search(for query: String) {
        searchNavigationController?.popToRootViewController(animated: false)
        searchController.search(for: query)

        if #available(iOS 26.0, *) {
            selectedTab = tabs.last
        } else {
            selectedViewController = searchNavigationController
        }
    }

    override func viewDidLayoutSubviews() {
        updateFrame()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        originalFrame = .init(origin: self.originalFrame.origin, size: size)
        shrunkFrame = self.originalFrame
        coordinator.animate { _ in
            self.view.setNeedsLayout()
        } completion: { _ in
            let bannerHeight = (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.totalBannerHeight ?? 0
            self.shrunkFrame = .init(
                x: self.originalFrame.origin.x,
                y: self.originalFrame.origin.y + bannerHeight,
                width: self.originalFrame.width,
                height: self.originalFrame.height - bannerHeight
            )
            self.updateFrame(animated: true)
        }
    }
}

extension TabBarController: UITabBarControllerDelegate {
    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        checkForSettingsPop()
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if #unavailable(iOS 18.0) {
            checkForSettingsPop()
        }
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        guard selectedTab?.identifier == tab.identifier else { return true }

        if tab.identifier == "library", let libraryViewController {
            libraryViewController.scrollToTop()
        } else if tab.identifier == "browse" {
            scrollCurrentViewToTop(in: browseNavigationController)
        } else if tab.identifier == "history" {
            handleHistoryReselection()
        } else if tab.identifier == "settings" {
            popSettingsToRoot()
            scrollSettingsToTop()
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard viewController === selectedViewController else { return true }

        if let navigationController = viewController as? UINavigationController,
           navigationController.viewControllers.first === libraryViewController {
            libraryViewController?.scrollToTop()
        } else if viewController === browseNavigationController {
            scrollCurrentViewToTop(in: browseNavigationController)
        } else if viewController === historyNavigationController {
            handleHistoryReselection()
        } else if viewController === settingsPath?.rootViewController || viewController === settingsPath?.navigationController {
            popSettingsToRoot()
            scrollSettingsToTop()
        }
        return true
    }

    private func checkForSettingsPop() {
        let isSettingsSelected: Bool
        if #available(iOS 26.0, *) {
            isSettingsSelected = selectedTab?.identifier == "settings"
        } else {
            isSettingsSelected = selectedViewController === settingsViewController
        }
        if selectedIndex == previousSelectedIndex && isSettingsSelected {
            popSettingsToRoot()
        }
        previousSelectedIndex = selectedIndex
    }

    private func checkForHistoryReselection() {
        guard
            AppSettings.library.continueReadingOnReselect.get(),
            let historyNavigationController,
            selectedViewController === historyNavigationController,
            historyNavigationController.viewControllers.count == 1,
            let scrollView = historyNavigationController.topViewController?.view.firstScrollView(),
            scrollView.isScrolledToTop
        else { return }
        NotificationCenter.default.post(name: .historyTabReselected, object: nil)
    }

    private func handleHistoryReselection() {
        guard let historyNavigationController,
              historyNavigationController.viewControllers.count == 1,
              let scrollView = historyNavigationController.topViewController?.view.firstScrollView()
        else { return }

        if scrollView.isScrolledToTop {
            checkForHistoryReselection()
        } else {
            scrollView.performSystemScrollToTop(animated: true)
        }
    }

    private func scrollCurrentViewToTop(in navigationController: UINavigationController?) {
        guard let scrollView = navigationController?.topViewController?.view.firstScrollView() else { return }
        if !scrollView.performSystemScrollToTop(animated: true) {
            let offset = CGPoint(
                x: -scrollView.adjustedContentInset.left,
                y: -scrollView.adjustedContentInset.top
            )
            scrollView.setContentOffset(offset, animated: true)
        }
    }

    private func popSettingsToRoot() {
        NotificationCenter.default.post(name: .init("settings.navigation.reset"), object: nil)
        settingsPath?.navigationController?.popToRootViewController(animated: true)
    }

    private func scrollSettingsToTop() {
        guard let root = settingsPath?.rootViewController else { return }
        func findScrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView,
               scrollView.scrollsToTop,
               !scrollView.isHidden,
               scrollView.alpha > 0 {
                return scrollView
            }
            for child in view.subviews {
                if let scrollView = findScrollView(in: child) { return scrollView }
            }
            return nil
        }
        let navigationController = settingsPath?.navigationController
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationController?.viewControllers.first?.navigationItem.largeTitleDisplayMode = .always

        if let scrollView = findScrollView(in: root.view) {
            if scrollView.performSystemScrollToTop(animated: true) {
                return
            }

            // SwiftUI's adjusted inset only reflects the currently visible part
            // of the navigation bar. Its intrinsic height also includes the
            // hidden large title and search field, giving us the true top edge.
            let hiddenNavigationBarHeight = navigationController.map {
                max(0, $0.navigationBar.intrinsicContentSize.height - $0.navigationBar.bounds.height)
            } ?? 0
            let expandedTopInset = scrollView.adjustedContentInset.top + hiddenNavigationBarHeight
            let offset = CGPoint(
                x: -scrollView.adjustedContentInset.left,
                y: -expandedTopInset
            )
            scrollView.setContentOffset(offset, animated: true)
        }
    }
}

// MARK: - Keyboard Shortcuts
extension TabBarController {
    override var keyCommands: [UIKeyCommand]? {
        tabBar.items?.enumerated().map { index, item in
            UIKeyCommand(
                title: item.title ?? "Tab \(index + 1)",
                action: #selector(selectTab),
                input: "\(index + 1)",
                modifierFlags: .shiftOrCommand,
                alternates: [],
                attributes: [],
                state: .off
            )
        }
    }

    @objc private func selectTab(sender: UIKeyCommand) {
        guard
            let input = sender.input,
            let newIndex = Int(input),
            newIndex >= 1 && newIndex <= (tabBar.items?.count ?? 0)
        else { return }
        selectedIndex = newIndex - 1
    }

    override var canBecomeFirstResponder: Bool { true }
}
