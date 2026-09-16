//
//  GeneralSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

import UIKit

struct GeneralSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            incognitoMode,
            flareSolverrURL,
            flareSolverrFallback
        ]
    }

    let incognitoMode = SettingsKey<Bool>("General.incognitoMode", default: false)
    let flareSolverrURL = SettingsKey<String>("General.flareSolverrURL", default: "")
    let flareSolverrFallback = SettingsKey<Bool>("General.flareSolverrFallback", default: true)
}
