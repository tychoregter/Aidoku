//
//  TrackingSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

struct TrackingSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            updateAfterReading,
            autoSyncFromTracker,
            onlyUpdateLibraryItems
        ]
    }

    let updateAfterReading = SettingsKey<Bool>("Tracking.updateAfterReading", default: true)
    let autoSyncFromTracker = SettingsKey<Bool>("Tracking.autoSyncFromTracker", default: false)
    let onlyUpdateLibraryItems = SettingsKey<Bool>("Tracking.onlyUpdateLibraryItems", default: false)
}
