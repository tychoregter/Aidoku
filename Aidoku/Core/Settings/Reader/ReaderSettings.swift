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
            thumbnailScrubber,
            autoScrollPosition
        ]
    }

    let automaticallyHideControls = SettingsKey<Bool>("Reader.automaticallyHideControls", default: true)
    let thumbnailScrubber = SettingsKey<Bool>("Reader.thumbnailScrubber", default: true)
    let autoScrollPosition = SettingsKey<AutoScrollPosition>("Reader.autoScrollPosition", default: .right)
}
