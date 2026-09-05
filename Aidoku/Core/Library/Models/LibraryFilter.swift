//
//  LibraryFilter.swift
//  Aidoku
//
//  Created by skitty on 3/17/26.
//

import UIKit

struct LibraryFilter: Codable, Hashable {
    var type: FilterMethod
    var value: String?
    var exclude: Bool

    enum Genre: String, CaseIterable, Hashable {
        case action = "Action"
        case adventure = "Adventure"
        case comedy = "Comedy"
        case crime = "Crime"
        case drama = "Drama"
        case ecchi = "Ecchi"
        case fantasy = "Fantasy"
        case hentai = "Hentai"
        case harem = "Harem"
        case historical = "Historical"
        case horror = "Horror"
        case martialArts = "Martial Arts"
        case mature = "Mature"
        case mecha = "Mecha"
        case military = "Military"
        case mystery = "Mystery"
        case psychological = "Psychological"
        case romance = "Romance"
        case schoolLife = "School Life"
        case sciFi = "Sci-Fi"
        case sliceOfLife = "Slice of Life"
        case sports = "Sports"
        case supernatural = "Supernatural"
        case thriller = "Thriller"
        case tragedy = "Tragedy"
        case yuri = "Yuri"

        var title: String { rawValue }

        var aliases: [String] {
            switch self {
                case .hentai: [rawValue, "Erotica"]
                case .yuri: [rawValue, "Girls' Love", "Girls’ Love"]
                default: [rawValue]
            }
        }

        func matches(_ value: String) -> Bool {
            let normalizedValue = Self.normalize(value)
            return aliases.contains { Self.normalize($0) == normalizedValue }
        }

        static func normalize(_ value: String) -> String {
            value
                .folding(options: .diacriticInsensitive, locale: .current)
                .replacingOccurrences(of: "’", with: "'")
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
                .lowercased()
        }
    }

    enum FilterMethod: Int, Codable, CaseIterable {
        case downloaded
        case tracking
        case hasUnread
        case started
        case completed
        case source
        case contentRating
        case category
        case favorite
        case caughtUp
        case collection
        case genre

        var title: String {
            switch self {
                case .downloaded: NSLocalizedString("DOWNLOADED")
                case .tracking: NSLocalizedString("IS_TRACKING")
                case .hasUnread: NSLocalizedString("FILTER_HAS_UNREAD")
                case .started: NSLocalizedString("FILTER_STARTED")
                case .completed: NSLocalizedString("STATUS_COMPLETED")
                case .source: NSLocalizedString("SOURCES")
                case .contentRating: NSLocalizedString("CONTENT_RATING")
                case .category: NSLocalizedString("CATEGORY")
                case .favorite: NSLocalizedString("FAVORITE")
                case .caughtUp: NSLocalizedString("CAUGHT_UP")
                case .collection: NSLocalizedString("COLLECTIONS")
                case .genre: NSLocalizedString("GENRE")
            }
        }

        var systemImageName: String {
            switch self {
                case .downloaded: "arrow.down.circle"
                case .tracking: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
                case .hasUnread: "eye.slash"
                case .started: "clock"
                case .completed: "checkmark.circle"
                case .source: "globe"
                case .contentRating: "exclamationmark.triangle"
                case .category: "folder"
                case .favorite: "star"
                case .caughtUp: "arrow.right.circle"
                case .collection: "rectangle.stack"
                case .genre: "tag"
            }
        }

        var image: UIImage? {
            UIImage(systemName: systemImageName)
        }

        var isAvailable: Bool {
            switch self {
                case .tracking: TrackerManager.hasAvailableTrackers
                case .source, .contentRating, .category, .collection, .genre: false // needs custom handling
                default: true
            }
        }

        var usesValueInSubtitle: Bool {
            switch self {
                case .contentRating, .category, .collection, .genre: true
                default: false
            }
        }

        var defaultsToExcluded: Bool {
            switch self {
                case .contentRating, .category, .collection: true
                default: false
            }
        }
    }

}
