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
            labsFeatures,
            developerMode,
            flareSolverrURL,
            flareSolverrFallback
        ]
    }

    let incognitoMode = SettingsKey<Bool>("General.incognitoMode", default: false)
    let labsFeatures = SettingsKey<Bool>("General.labsFeatures", default: false)
    let developerMode = SettingsKey<Bool>("General.developerMode", default: false)
    let flareSolverrURL = SettingsKey<String>("General.flareSolverrURL", default: "")
    let flareSolverrFallback = SettingsKey<Bool>("General.flareSolverrFallback", default: true)
}

/// Screenshot-safe presentation values. These never replace stored manga data.
enum DeveloperMode {
    static var enabled: Bool { AppSettings.general.developerMode.get() }

    private static func index(for identifier: String, count: Int) -> Int {
        let hash = identifier.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
    }

    static func title(for identifier: String) -> String {
        let titles = [
            "The Quiet Horizon", "A City of Stars", "The Last Summer", "Beyond the Valley",
            "The Moonlit Garden", "A Distant Promise", "Where Rivers Meet", "The Hidden Path",
            "A Place to Begin", "Under Open Skies", "The Faraway Shore", "A Gentle Season",
            "Between Two Worlds", "The Winding Road", "Notes from Tomorrow", "A World Apart",
            "The Little Things", "Across the Blue", "When We Were Young", "The Long Way Home",
            "A New Book", "Beneath the Lanterns", "The Morning After", "Somewhere, Someday",
            "The Shape of Things", "A Thousand Miles", "Our Secret Garden", "The Turning Point",
            "Light Through the Leaves", "The Other Side of Spring", "A Story Untold", "Far from Here"
        ]
        return titles[index(for: identifier, count: titles.count)]
    }

    static func author(for identifier: String) -> String {
        let authors = ["Mira Ellis", "Alex Morgan", "Nora Bennett", "Evan Cole", "Jamie Rivers", "Robin Hale", "Taylor Brooks", "Casey Lane"]
        return authors[index(for: identifier, count: authors.count)]
    }

    static func chapterTitle(for identifier: String) -> String {
        let titles = ["A New Beginning", "An Unexpected Visit", "The Road Ahead", "After the Rain", "A Change of Plans", "An Old Friend", "The Next Morning", "Finding Our Way"]
        return titles[index(for: identifier, count: titles.count)]
    }

    static func tag(for identifier: String) -> String {
        let tags = ["adventure", "drama", "friendship", "mystery", "slice of life", "comedy"]
        return tags[index(for: identifier, count: tags.count)]
    }

    static func description(for identifier: String) -> String {
        let descriptions = [
            "A chance encounter leads to a new journey. Along the way, old friends and new faces discover that even the smallest decisions can change everything.",
            "In a town full of stories, one unlikely friendship opens the door to new possibilities. Each day brings another reason to look ahead.",
            "When a familiar place begins to change, a group of friends sets out to find what matters most. Their journey is only just beginning."
        ]
        return descriptions[index(for: identifier, count: descriptions.count)]
    }

    static func color(for identifier: String) -> UIColor {
        let colors: [UIColor] = [
            UIColor(red: 0.55, green: 0.62, blue: 0.67, alpha: 1),
            UIColor(red: 0.66, green: 0.58, blue: 0.57, alpha: 1),
            UIColor(red: 0.55, green: 0.64, blue: 0.59, alpha: 1),
            UIColor(red: 0.64, green: 0.60, blue: 0.68, alpha: 1),
            UIColor(red: 0.67, green: 0.62, blue: 0.54, alpha: 1)
        ]
        return colors[index(for: identifier, count: colors.count)]
    }

    static func pageCount(for identifier: String) -> Int {
        18 + index(for: identifier, count: 31)
    }
}
