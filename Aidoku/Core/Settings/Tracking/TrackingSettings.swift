//
//  TrackingSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

import Foundation

struct TrackingSettings: Sendable {
    enum KomgaProgressSyncInterval: String, SettingsValue, CaseIterable {
        case appLaunchAndRefresh
        case everyMinute
        case everyFiveMinutes
        case everyThirtyMinutes

        var title: String {
            switch self {
                case .appLaunchAndRefresh: NSLocalizedString("APP_LAUNCH_AND_REFRESH")
                case .everyMinute: NSLocalizedString("EVERY_MINUTE")
                case .everyFiveMinutes: NSLocalizedString("EVERY_FIVE_MINUTES")
                case .everyThirtyMinutes: NSLocalizedString("EVERY_THIRTY_MINUTES")
            }
        }

        /// The grace period used for app launch/activation checks and the
        /// lifetime of Komga's in-memory progress response cache. A nil value
        /// means that timed activation checks are disabled.
        var timeInterval: TimeInterval? {
            switch self {
                case .appLaunchAndRefresh: nil
                case .everyMinute: 60
                case .everyFiveMinutes: 5 * 60
                case .everyThirtyMinutes: 30 * 60
            }
        }
    }

    var keys: [any SettingsDefault] {
        [
            updateAfterReading,
            autoSyncFromTracker,
            onlyUpdateLibraryItems,
            komgaProgressSyncInterval
        ]
    }

    let updateAfterReading = SettingsKey<Bool>("Tracking.updateAfterReading", default: true)
    let autoSyncFromTracker = SettingsKey<Bool>("Tracking.autoSyncFromTracker", default: false)
    let onlyUpdateLibraryItems = SettingsKey<Bool>("Tracking.onlyUpdateLibraryItems", default: false)
    let komgaProgressSyncInterval = SettingsKey<KomgaProgressSyncInterval>(
        "Tracking.komgaProgressSyncInterval",
        default: .everyFiveMinutes
    )
}
