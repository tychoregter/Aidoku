//
//  AppearanceSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

import UIKit

struct AppearanceSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            useSystemAppearance,
            appearance,
            layout,
            customPortraitRows,
            customLandscapeRows,
            dedicatedBrowseTab,
            dedicatedHistoryTab,
            dedicatedFavoritesTab,
            dedicatedSettingsTab,
            dedicatedSearchTab,
            dedicatedUpdatesTab,
            navigationTabOrder,
            collapseNavigationWhenScrolling,
            separatePinnedTitles,
            showPinnedSectionTitles,
            keepPinnedTitlesInLibrary,
            horizontalPinnedTitles,
            dedicatedContinueReadingSection,
            blurNSFWCovers,
            grayscaleCaughtUpCovers
        ]
    }

    let useSystemAppearance = SettingsKey<Bool>("General.useSystemAppearance", default: true)
    let appearance = SettingsKey<Int>("General.appearance", default: 0)

    let layout = SettingsKey<Layout>("Appearance.layout", default: .standard)
    let customPortraitRows = SettingsKey<Int>("Appearance.customPortraitRows", default: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2)
    let customLandscapeRows = SettingsKey<Int>("Appearance.customLandscapeRows", default: UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4)
    let dedicatedBrowseTab = SettingsKey<Bool>("Appearance.dedicatedBrowseTab", default: true)
    let dedicatedHistoryTab = SettingsKey<Bool>("Appearance.dedicatedHistoryTab", default: false)
    let dedicatedFavoritesTab = SettingsKey<Bool>("Appearance.dedicatedFavoritesTab", default: false)
    let dedicatedSettingsTab = SettingsKey<Bool>("Appearance.dedicatedSettingsTab", default: false)
    let dedicatedSearchTab = SettingsKey<Bool>("Appearance.dedicatedSearchTab", default: true)
    let dedicatedUpdatesTab = SettingsKey<Bool>("Appearance.dedicatedUpdatesTab", default: false)
    let navigationTabOrder = SettingsKey<[String]>("Appearance.navigationTabOrder", default: NavigationTab.allCases.map(\.rawValue))
    let collapseNavigationWhenScrolling = SettingsKey<Bool>("Appearance.collapseNavigationWhenScrolling", default: false)
    let separatePinnedTitles = SettingsKey<Bool>("Appearance.separatePinnedTitles", default: true)
    let showPinnedSectionTitles = SettingsKey<Bool>("Appearance.showPinnedSectionTitles", default: true)
    let keepPinnedTitlesInLibrary = SettingsKey<Bool>("Appearance.keepPinnedTitlesInLibrary", default: false)
    let horizontalPinnedTitles = SettingsKey<Bool>("Appearance.horizontalPinnedTitles", default: true)
    let dedicatedContinueReadingSection = SettingsKey<Bool>("Appearance.dedicatedContinueReadingSection", default: true)
    let blurNSFWCovers = SettingsKey<Bool>("Appearance.blurNSFWCovers", default: false)
    let grayscaleCaughtUpCovers = SettingsKey<Bool>("Appearance.grayscaleCaughtUpCovers", default: false)
}

enum NavigationTab: String, CaseIterable, Identifiable {
    case library, favorites, browse, history, updates, settings, search

    var id: String { rawValue }

    static var ordered: [Self] {
        let saved = AppSettings.appearance.navigationTabOrder.get().compactMap(Self.init(rawValue:))
        var result: [Self] = []
        for tab in saved + allCases where !result.contains(tab) {
            result.append(tab)
        }
        return result
    }

    var isEnabled: Bool {
        switch self {
            case .library: true
            case .favorites: AppSettings.appearance.dedicatedFavoritesTab.get()
            case .browse: AppSettings.appearance.dedicatedBrowseTab.get()
            case .history: AppSettings.appearance.dedicatedHistoryTab.get()
            case .updates: AppSettings.appearance.dedicatedUpdatesTab.get()
            case .settings: AppSettings.appearance.dedicatedSettingsTab.get()
            case .search: AppSettings.appearance.dedicatedSearchTab.get()
        }
    }

    var settingKey: String? {
        switch self {
            case .library: nil
            case .favorites: AppSettings.appearance.dedicatedFavoritesTab.key
            case .browse: AppSettings.appearance.dedicatedBrowseTab.key
            case .history: AppSettings.appearance.dedicatedHistoryTab.key
            case .updates: AppSettings.appearance.dedicatedUpdatesTab.key
            case .settings: AppSettings.appearance.dedicatedSettingsTab.key
            case .search: AppSettings.appearance.dedicatedSearchTab.key
        }
    }

    var title: String {
        switch self {
            case .library: NSLocalizedString("LIBRARY")
            case .favorites: "Favorites"
            case .browse: NSLocalizedString("BROWSE")
            case .history: NSLocalizedString("HISTORY")
            case .updates: NSLocalizedString("MANGA_UPDATES")
            case .settings: NSLocalizedString("SETTINGS")
            case .search: NSLocalizedString("SEARCH")
        }
    }
}
