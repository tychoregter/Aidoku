//
//  NavigationController.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 11/02/2024.
//

import UIKit

class NavigationController: UINavigationController {
    private var statusBarStyleOverride: (owner: UUID, style: UIStatusBarStyle)?

    override var childForStatusBarStyle: UIViewController? {
        statusBarStyleOverride == nil ? super.childForStatusBarStyle : nil
    }

    func setStatusBarStyleOverride(_ style: UIStatusBarStyle?, owner: UUID) {
        if let style {
            guard statusBarStyleOverride?.owner != owner || statusBarStyleOverride?.style != style else { return }
            statusBarStyleOverride = (owner, style)
        } else {
            guard statusBarStyleOverride?.owner == owner else { return }
            statusBarStyleOverride = nil
        }
        setNeedsStatusBarAppearanceUpdate()
        tabBarController?.setNeedsStatusBarAppearanceUpdate()
    }

    // This is a workaround to fix an iOS bug that occurs when mixing UIKit with SwiftUI,
    // that causes the current TabBarItem title to be lost when navigating inside SwiftUI views.
    // See: https://stackoverflow.com/questions/62662313/uitabbar-containing-swiftui-view
    private var storedTabBarItem: UITabBarItem?
    override var tabBarItem: UITabBarItem! {
        get { storedTabBarItem ?? super.tabBarItem }
        set { storedTabBarItem = newValue }
    }

    // fix for incognito mode banner status bar text being the wrong color sometimes on ios 26+
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if let statusBarStyleOverride {
            return statusBarStyleOverride.style
        }
        if AppSettings.general.incognitoMode.get() {
            return traitCollection.userInterfaceStyle == .light ? .darkContent : .lightContent
        } else {
            return .default
        }
    }
}
