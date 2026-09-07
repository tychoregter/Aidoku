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
            separatePinnedTitles,
            showPinnedSectionTitles,
            keepPinnedTitlesInLibrary,
            horizontalPinnedTitles
        ]
    }

    let useSystemAppearance = SettingsKey<Bool>("General.useSystemAppearance", default: true)
    let appearance = SettingsKey<Int>("General.appearance", default: 0)

    let layout = SettingsKey<Layout>("Appearance.layout", default: .standard)
    let customPortraitRows = SettingsKey<Int>("Appearance.customPortraitRows", default: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2)
    let customLandscapeRows = SettingsKey<Int>("Appearance.customLandscapeRows", default: UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4)
    let dedicatedBrowseTab = SettingsKey<Bool>("Appearance.dedicatedBrowseTab", default: false)
    let dedicatedHistoryTab = SettingsKey<Bool>("Appearance.dedicatedHistoryTab", default: false)
    let separatePinnedTitles = SettingsKey<Bool>("Appearance.separatePinnedTitles", default: false)
    let showPinnedSectionTitles = SettingsKey<Bool>("Appearance.showPinnedSectionTitles", default: true)
    let keepPinnedTitlesInLibrary = SettingsKey<Bool>("Appearance.keepPinnedTitlesInLibrary", default: false)
    let horizontalPinnedTitles = SettingsKey<Bool>("Appearance.horizontalPinnedTitles", default: false)
}
