//
//  ReaderSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

struct ReaderSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            automaticallyHideControls,
            autoScrollPosition,
            useLegacyScrubber,
            scrubberDataSaver,
            showWebtoonScrollPercentage
        ]
    }

    let automaticallyHideControls = SettingsKey<Bool>("Reader.automaticallyHideControls", default: true)
    let autoScrollPosition = SettingsKey<AutoScrollPosition>("Reader.autoScrollPosition", default: .right)
    let useLegacyScrubber = SettingsKey<Bool>("Reader.useLegacyScrubber", default: false)
    let scrubberDataSaver = SettingsKey<Bool>("Reader.scrubberDataSaver", default: false)
    let showWebtoonScrollPercentage = SettingsKey<Bool>("Reader.showWebtoonScrollPercentage", default: true)
}
