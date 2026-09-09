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
            pageTurnEffect,
            autoScrollPosition
        ]
    }

    let automaticallyHideControls = SettingsKey<Bool>("Reader.automaticallyHideControls", default: true)
    let pageTurnEffect = SettingsKey<PageTurnEffect>("Reader.pageTurnEffect", default: .slide)
    let autoScrollPosition = SettingsKey<AutoScrollPosition>("Reader.autoScrollPosition", default: .right)
}
