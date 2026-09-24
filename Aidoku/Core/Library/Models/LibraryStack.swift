//
//  LibraryStack.swift
//  Aidoku
//

import Foundation

enum LibraryBundleFeature {
    // Flip this back to true to restore Bundle entry points without migrating stored data.
    static let isEnabled = false
}

struct LibraryStack: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let dateCreated: Date
    var members: [MangaIdentifier]
    var coverManga: MangaIdentifier?
    var customCoverFileName: String?
}

struct BackupLibraryStack: Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let dateCreated: Date
    let members: [MangaIdentifier]
    let coverManga: MangaIdentifier?
    let customCover: Data?
}
