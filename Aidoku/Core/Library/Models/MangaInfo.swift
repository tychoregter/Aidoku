//
//  MangaInfo.swift
//  Aidoku
//
//  Created by Skitty on 8/7/22.
//

import Foundation

struct MangaInfo: Hashable, Sendable {
    private static let emptyPinnedPlaceholderSourceKey = "__empty_pinned_placeholder__"

    let id: MangaIdentifier

    var coverUrl: URL?
    var title: String?
    var author: String?

    var url: URL?

    var unread: Int = 0
    var downloads: Int = 0
    var lastRead: Date?

    // Pin-specific event date. Reading combines eligible updates with reads;
    // Recently Updated uses the chapter-update date.
    var pinSortDate: Date?

    // Position in the library's selected sort order. Pinned sections can use
    // their own ordering while duplicate entries retain normal library order.
    var librarySortIndex: Int = 0

    // Used only when a title is intentionally shown in more than one library section.
    var displayVariant: String? = nil

    var isEmptyPinnedPlaceholder: Bool {
        id.sourceKey == Self.emptyPinnedPlaceholderSourceKey
    }

    static func emptyPinnedPlaceholder(title: String) -> MangaInfo {
        MangaInfo(
            id: MangaIdentifier(
                sourceKey: emptyPinnedPlaceholderSourceKey,
                mangaKey: "empty"
            ),
            title: title,
            displayVariant: "empty-pinned"
        )
    }

    func toManga() -> Manga {
        Manga(
            sourceId: id.sourceKey,
            id: id.mangaKey,
            title: title,
            author: author,
            coverUrl: coverUrl,
            url: url
        )
    }
}
