//
//  ReaderSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

struct ReaderSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            thumbnailScrubber,
            autoScrollPosition
        ]
    }

    let thumbnailScrubber = SettingsKey<Bool>("Reader.thumbnailScrubber", default: true)
    let autoScrollPosition = SettingsKey<AutoScrollPosition>("Reader.autoScrollPosition", default: .right)
}
