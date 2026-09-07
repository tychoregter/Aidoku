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

    struct Genre: Hashable, Sendable {
        let rawValue: String
        let aliases: [String]

        var title: String { rawValue }

        init(rawValue: String, aliases: [String]? = nil) {
            self.rawValue = rawValue
            self.aliases = aliases ?? [rawValue]
        }

        func matches(_ value: String) -> Bool {
            let normalizedValue = Self.normalize(value)
            return aliases.contains { Self.normalize($0) == normalizedValue }
        }

        static func normalize(_ value: String) -> String {
            LibraryGenreFilterSettings.normalize(value)
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

        /// The filter types presented in the Library menu that pinned titles can ignore.
        /// Value-based filters intentionally remain a single setting each.
        static let pinTitlesIgnoreFilterMethods: [Self] = [
            .favorite,
            .started,
            .caughtUp,
            .completed,
            .genre,
            .contentRating,
            .collection,
            .category,
            .source,
            .downloaded
        ]

        static let configurableThreeStateFilterMethods: [Self] = [
            .contentRating,
            .collection,
            .category,
            .source
        ]

        /// The top-level filter entries shown in the Library filter menu.
        /// Value-based filters remain one entry here; their submenu values
        /// are configured within the filter itself.
        static let menuFilterMethods: [Self] = [
            .favorite, .started, .caughtUp, .completed,
            .contentRating, .collection, .category, .source, .genre, .downloaded
        ]

        var threeStateFilterIdentifier: String {
            String(rawValue)
        }

        var pinTitlesIgnoreFilterIdentifier: String {
            String(rawValue)
        }

        static func pinTitlesIgnoreFilterMethod(for identifier: String) -> Self? {
            pinTitlesIgnoreFilterMethods.first {
                $0.pinTitlesIgnoreFilterIdentifier == identifier
            }
        }

        var title: String {
            switch self {
                case .downloaded: NSLocalizedString("DOWNLOADED")
                case .tracking: NSLocalizedString("IS_TRACKING")
                case .hasUnread: NSLocalizedString("FILTER_HAS_UNREAD")
                case .started: NSLocalizedString("FILTER_STARTED")
                case .completed: NSLocalizedString("FILTER_ENDED", value: "Ended", comment: "Library filter for series that have ended")
                case .source: Bundle.main.localizedString(forKey: "SOURCE", value: "Source", table: nil)
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
                case .source, .contentRating, .category, .collection, .genre: true
                default: false
            }
        }

        var defaultsToExcluded: Bool {
            switch self {
                case .contentRating, .category, .collection, .source:
                    AppSettings.library.threeStateFilterMethods.get().contains(threeStateFilterIdentifier)
                default: false
            }
        }
    }

}

struct LibraryGenreFilterConfiguration: Codable, Hashable, Sendable {
    var enabledOverrides: [String: Bool] = [:]
    var links: [String: String] = [:]
}

enum LibraryGenreFilterSettings {
    private static let defaultEnabledNames = [
        "Action", "Adventure", "Comedy", "Crime", "Drama", "Fantasy", "Historical", "Horror",
        "Martial Arts", "Mature", "Mecha", "Military", "Mystery", "Psychological", "Romance",
        "School Life", "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller", "Tragedy"
    ]

    private static let preferredTitles = [
        "martial arts": "Martial Arts",
        "school life": "School Life",
        "sci-fi": "Sci-Fi",
        "slice of life": "Slice of Life",
        "girls' love": "Girls' Love",
        "yuri": "Yuri",
        "hentai": "Hentai",
        "erotica": "Erotica"
    ]

    private static var defaultEnabledIDs: Set<String> {
        Set(defaultEnabledNames.map(normalize))
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    static func load() -> LibraryGenreFilterConfiguration {
        if let data = AppSettings.library.genreFilterConfigurationData.get(),
           let configuration = try? JSONDecoder().decode(LibraryGenreFilterConfiguration.self, from: data) {
            return configuration
        }
        return .init()
    }

    static func save(_ configuration: LibraryGenreFilterConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        AppSettings.library.genreFilterConfigurationData.set(data)
    }

    static func uniqueGenreNames(_ values: [String]) -> [String] {
        var names: [String: String] = [:]
        for value in values {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let identifier = normalize(trimmedValue)
            guard !identifier.isEmpty, names[identifier] == nil else { continue }
            names[identifier] = displayName(for: identifier, fallback: trimmedValue)
        }
        return names.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func rootIdentifier(for value: String, configuration: LibraryGenreFilterConfiguration) -> String {
        var current = normalize(value)
        var visited: Set<String> = []
        while let next = configuration.links[current], visited.insert(current).inserted {
            current = normalize(next)
        }
        return current
    }

    static func isEnabled(_ value: String, configuration: LibraryGenreFilterConfiguration) -> Bool {
        let identifier = rootIdentifier(for: value, configuration: configuration)
        return configuration.enabledOverrides[identifier] ?? defaultEnabledIDs.contains(identifier)
    }

    static func setEnabled(
        _ enabled: Bool,
        for value: String,
        configuration: inout LibraryGenreFilterConfiguration
    ) {
        let identifier = rootIdentifier(for: value, configuration: configuration)
        configuration.enabledOverrides[identifier] = enabled
    }

    static func link(
        _ value: String,
        to target: String,
        configuration: inout LibraryGenreFilterConfiguration
    ) {
        let identifier = normalize(value)
        let targetIdentifier = rootIdentifier(for: target, configuration: configuration)
        guard identifier != targetIdentifier else { return }
        configuration.links[identifier] = targetIdentifier
    }

    static func unlink(_ value: String, configuration: inout LibraryGenreFilterConfiguration) {
        configuration.links.removeValue(forKey: normalize(value))
    }

    static func linkedTarget(
        for value: String,
        availableNames: [String],
        configuration: LibraryGenreFilterConfiguration
    ) -> String? {
        let identifier = normalize(value)
        guard configuration.links[identifier] != nil else { return nil }
        let root = rootIdentifier(for: value, configuration: configuration)
        return displayName(for: root, availableNames: availableNames)
    }

    static func isLinked(
        _ value: String,
        to target: String,
        configuration: LibraryGenreFilterConfiguration
    ) -> Bool {
        normalize(value) != normalize(target)
            && rootIdentifier(for: value, configuration: configuration)
                == rootIdentifier(for: target, configuration: configuration)
    }

    static func availableFilterGenres(
        from values: [String],
        configuration: LibraryGenreFilterConfiguration
    ) -> [LibraryFilter.Genre] {
        let names = uniqueGenreNames(values)
        var aliasesByRoot: [String: [String]] = [:]
        for name in names {
            let root = rootIdentifier(for: name, configuration: configuration)
            aliasesByRoot[root, default: []].append(name)
        }

        return aliasesByRoot.compactMap { root, aliases in
            guard isEnabled(root, configuration: configuration) else { return nil }
            let title = displayName(for: root, availableNames: names)
            return LibraryFilter.Genre(rawValue: title, aliases: aliases)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func matchingGenre(
        for value: String,
        in genres: [LibraryFilter.Genre],
        configuration: LibraryGenreFilterConfiguration
    ) -> LibraryFilter.Genre? {
        let root = rootIdentifier(for: value, configuration: configuration)
        return genres.first {
            rootIdentifier(for: $0.rawValue, configuration: configuration) == root
        }
    }

    static func displayName(for identifier: String, availableNames: [String]) -> String {
        if let availableName = availableNames.first(where: { normalize($0) == identifier }) {
            return availableName
        }
        return displayName(for: identifier, fallback: identifier)
    }

    private static func displayName(for identifier: String, fallback: String) -> String {
        if let preferredTitle = preferredTitles[identifier] {
            return preferredTitle
        }
        guard let first = fallback.first else { return fallback }
        return first.uppercased() + String(fallback.dropFirst())
    }
}
