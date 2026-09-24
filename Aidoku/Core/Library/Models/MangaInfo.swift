//
//  MangaInfo.swift
//  Aidoku
//
//  Created by Skitty on 8/7/22.
//

import Foundation

struct MangaInfo: Hashable, Sendable {
    private static let emptyPinnedPlaceholderSourceKey = "__empty_pinned_placeholder__"
    private static let libraryStackSourceKey = "__library_stack__"

    let id: MangaIdentifier

    var coverUrl: URL?
    var coverIdentifier: MangaIdentifier?
    var title: String?
    var author: String?
    var isNSFW: Bool = false

    var url: URL?

    var unread: Int = 0
    var downloads: Int = 0
    var lastRead: Date?
    var libraryLastOpened: Date?
    var libraryLastUpdated: Date?
    var libraryDateAdded: Date?
    var libraryLastChapter: Date?
    var totalChapters: Int = 0

    // Pin-specific event date. Reading combines eligible updates with reads;
    // Recently Updated uses the chapter-update date.
    var pinSortDate: Date?

    // Position in the library's selected sort order. Pinned sections can use
    // their own ordering while duplicate entries retain normal library order.
    var librarySortIndex: Int = 0

    // Used only when a title is intentionally shown in more than one library section.
    var displayVariant: String? = nil

    var stackItemCount: Int = 0
    var stackDateCreated: Date?

    var stackID: UUID? {
        guard id.sourceKey == Self.libraryStackSourceKey else { return nil }
        return UUID(uuidString: id.mangaKey)
    }

    var isLibraryStack: Bool { stackID != nil }

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

    static func libraryStack(
        id: UUID,
        title: String,
        coverURL: URL?,
        coverIdentifier: MangaIdentifier?,
        itemCount: Int,
        dateCreated: Date,
        unread: Int,
        downloads: Int,
        lastRead: Date?,
        lastOpened: Date?,
        lastUpdated: Date?,
        lastChapter: Date?,
        totalChapters: Int,
        librarySortIndex: Int,
        isNSFW: Bool
    ) -> MangaInfo {
        MangaInfo(
            id: MangaIdentifier(sourceKey: libraryStackSourceKey, mangaKey: id.uuidString),
            coverUrl: coverURL,
            coverIdentifier: coverIdentifier,
            title: title,
            author: String(format: NSLocalizedString("%d items", comment: "Number of items in a Stack"), itemCount),
            isNSFW: isNSFW,
            unread: unread,
            downloads: downloads,
            lastRead: lastRead,
            libraryLastOpened: lastOpened,
            libraryLastUpdated: lastUpdated,
            libraryDateAdded: dateCreated,
            libraryLastChapter: lastChapter,
            totalChapters: totalChapters,
            librarySortIndex: librarySortIndex,
            stackItemCount: itemCount,
            stackDateCreated: dateCreated
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
