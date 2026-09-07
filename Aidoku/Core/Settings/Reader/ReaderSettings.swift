//
//  ReaderSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

struct ReaderSettings: Sendable {
    var keys: [any SettingsDefault] {
        [thumbnailScrubber, compactThumbnailScrubber]
    }

    let thumbnailScrubber = SettingsKey<Bool>("Reader.thumbnailScrubber", default: true)
    let compactThumbnailScrubber = SettingsKey<Bool>("Reader.compactThumbnailScrubber", default: true)
}
