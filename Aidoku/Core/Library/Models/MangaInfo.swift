//
//  MangaInfo.swift
//  Aidoku
//
//  Created by Skitty on 8/7/22.
//

import Foundation

struct MangaInfo: Hashable, Sendable {
    let id: MangaIdentifier

    var coverUrl: URL?
    var title: String?
    var author: String?

    var url: URL?

    var unread: Int = 0
    var downloads: Int = 0
    var lastRead: Date?

    // Used only when a title is intentionally shown in more than one library section.
    var displayVariant: String? = nil

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
