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
                case .caughtUp: "checkmark.circle"
                case .collection: "rectangle.stack"
            }
        }

        var image: UIImage? {
            UIImage(systemName: systemImageName)
        }

        var isAvailable: Bool {
            switch self {
                case .tracking: TrackerManager.hasAvailableTrackers
                case .source, .contentRating, .category, .collection: false // needs custom handling
                default: true
            }
        }
    }

}
