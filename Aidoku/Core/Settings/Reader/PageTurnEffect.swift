//
//  PageTurnEffect.swift
//  Aidoku
//
//  Created by Codex on 9/9/26.
//

extension ReaderSettings {
    enum PageTurnEffect: String, SettingsValue, CaseIterable {
        case slide
        case curl

        var title: String {
            switch self {
                case .slide: NSLocalizedString("PAGE_TURN_EFFECT_SLIDE")
                case .curl: NSLocalizedString("PAGE_TURN_EFFECT_CURL")
            }
        }
    }
}
