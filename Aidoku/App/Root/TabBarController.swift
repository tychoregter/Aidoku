//
//  TabBarController.swift
//  Aidoku
//
//  Created by Skitty on 7/26/25.
//

import Combine
import SwiftUI
import SwiftUIIntrospect

class TabBarController: UITabBarController {
    private var originalFrame: CGRect = .zero
    private var shrunkFrame: CGRect = .zero
    private var cancellables: [AnyCancellable] = []

    private var settingsPath: NavigationCoordinator?
    private weak var libraryViewController: LibraryViewController?
    private var previousSelectedIndex: Int?

    private weak var searchNavigationController: UINavigationController?

    private let searchController = SearchViewController()
    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior = .onScrollDown
        }

        let libraryRootViewController = LibraryViewController()
        self.libraryViewController = libraryRootViewController
        let libraryViewController = NavigationController(rootViewController: libraryRootViewController)
        let searchViewController = NavigationController(rootViewController: searchController)
        searchNavigationController = searchViewController

        let settingsPath = NavigationCoordinator(rootViewController: nil)
        let settingsViewController: UIViewController
        if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom != .pad {
            settingsViewController = UIHostingController(
                rootView: NavigationStack {
                    SettingsView()
                        .environmentObject(settingsPath)
                }.introspect(.navigationStack, on: .iOS(.v26, .v27)) { entity in
                    settingsPath.rootViewController = entity
                }
            )
        } else {
            // this breaks the zoom transitions from the toolbar buttons in the backups setting page on ios 18 / ipads
            let hosting = UIHostingController(rootView: SettingsView().environmentObject(settingsPath))
            let entity = NavigationController(rootViewController: hosting)
            entity.navigationBar.prefersLargeTitles = true
            settingsPath.rootViewController = entity
            settingsViewController = entity
        }
        self.settingsPath = settingsPath

        libraryViewController.navigationBar.prefersLargeTitles = true
        searchViewController.navigationBar.prefersLargeTitles = true

        if #available(iOS 26.0, *) {
            let searchTab = UISearchTab { _ in
                searchViewController
            }
            searchTab.automaticallyActivatesSearch = true
            let fixedTabs = [
                UITab(
                    title: NSLocalizedString("LIBRARY"),
                    image: UIImage(systemName: "books.vertical.fill"),
                    identifier: "0"
                ) { _ in
                    libraryViewController
                },
                UITab(
                    title: NSLocalizedString("SETTINGS"),
                    image: UIImage(systemName: "gear"),
                    identifier: "2"
                ) { _ in
                    settingsViewController
                }
            ]
            fixedTabs.forEach {
                $0.allowsHiding = false
                $0.preferredPlacement = .fixed
            }
            tabs = fixedTabs + [searchTab]
        } else {
            libraryViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("LIBRARY"),
                image: UIImage(systemName: "books.vertical.fill"),
                tag: 0
            )
            searchViewController.tabBarItem = UITabBarItem(
                tabBarSystemItem: .search,
                tag: 2
            )
            settingsViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("SETTINGS"),
                image: UIImage(systemName: "gear"),
                tag: 3
            )
            viewControllers = [
                libraryViewController,
                searchViewController,
                settingsViewController
            ]
        }

        NotificationCenter.default.publisher(for: .init(AppSettings.general.incognitoMode.key))
            .sink { [weak self] _ in
                self?.updateFrame(animated: true)
            }
            .store(in: &cancellables)

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

    func showLibraryRefreshView() {
        // Background refreshes intentionally do not show the pull-to-refresh spinner.
    }

    func setLibraryRefreshProgress(_ progress: Float) {
        // Progress is used by background tasks only.
    }

    func hideAccessoryView() {
        // Background refreshes intentionally do not show an accessory.
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
        if tab.identifier == "0", let libraryViewController {
            libraryViewController.scrollToTop()
        } else if tab.identifier == "2" {
            popSettingsToRoot()
            scrollSettingsToTop()
        }
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if let navigationController = viewController as? UINavigationController,
           navigationController.viewControllers.first === libraryViewController {
            libraryViewController?.scrollToTop()
        } else if viewController === settingsPath?.rootViewController || viewController === settingsPath?.navigationController {
            popSettingsToRoot()
            scrollSettingsToTop()
        }
        return true
    }

    private func checkForSettingsPop() {
        let settingsIndex: Int
        if #available(iOS 26.0, *) {
            settingsIndex = 1
        } else {
            settingsIndex = 2
        }
        if selectedIndex == previousSelectedIndex && previousSelectedIndex == settingsIndex {
            popSettingsToRoot()
        }
        previousSelectedIndex = selectedIndex
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
            // SwiftUI's adjusted inset only reflects the currently visible part
            // of the navigation bar. Its intrinsic height also includes the
            // hidden large title and search field, giving us the true top edge.
            let hiddenNavigationBarHeight = navigationController.map {
                max(0, $0.navigationBar.intrinsicContentSize.height - $0.navigationBar.bounds.height)
            } ?? 0
            let expandedTopInset = scrollView.adjustedContentInset.top + hiddenNavigationBarHeight
            scrollView.setContentOffset(
                CGPoint(
                    x: -scrollView.adjustedContentInset.left,
                    y: -expandedTopInset
                ),
                animated: true
            )
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
