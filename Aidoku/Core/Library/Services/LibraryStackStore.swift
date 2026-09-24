//
//  LibraryStackStore.swift
//  Aidoku
//

import UIKit

@MainActor
final class LibraryStackStore {
    static let shared = LibraryStackStore()

    private static let directory = FileManager.default.applicationSupportDirectory
        .appendingPathComponent("LibraryStacks", isDirectory: true)
    private static let metadataURL = directory.appendingPathComponent("stacks.json")
    private static let coversDirectory = directory.appendingPathComponent("Covers", isDirectory: true)

    private(set) var stacks: [LibraryStack]

    private init() {
        stacks = (try? Data(contentsOf: Self.metadataURL))
            .flatMap { try? JSONDecoder().decode([LibraryStack].self, from: $0) } ?? []
        normalizeAndSaveIfNeeded()
    }

    var sortedStacks: [LibraryStack] {
        stacks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func stack(id: UUID) -> LibraryStack? {
        stacks.first { $0.id == id }
    }

    func stack(containing manga: MangaIdentifier) -> LibraryStack? {
        stacks.first { $0.members.contains(manga) }
    }

    func create(name: String, firstMember: MangaIdentifier) -> LibraryStack? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, isNameAvailable(name) else { return nil }
        let stack = LibraryStack(
            id: UUID(),
            name: name,
            dateCreated: .now,
            members: [firstMember],
            coverManga: firstMember,
            customCoverFileName: nil
        )
        remove(firstMember, deletingEmptyStack: true, notify: false)
        stacks.append(stack)
        saveAndNotify()
        return stack
    }

    func rename(id: UUID, name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, isNameAvailable(name, excluding: id),
              let index = stacks.firstIndex(where: { $0.id == id }) else { return false }
        stacks[index].name = name
        saveAndNotify()
        return true
    }

    func move(_ manga: MangaIdentifier, to stackID: UUID) {
        guard stacks.contains(where: { $0.id == stackID }) else { return }
        remove(manga, deletingEmptyStack: true, notify: false)
        guard let index = stacks.firstIndex(where: { $0.id == stackID }) else { return }
        stacks[index].members.append(manga)
        if stacks[index].coverManga == nil, stacks[index].customCoverFileName == nil {
            stacks[index].coverManga = manga
        }
        saveAndNotify()
    }

    func remove(_ manga: MangaIdentifier) {
        remove(manga, deletingEmptyStack: true, notify: true)
    }

    func delete(id: UUID) {
        guard let index = stacks.firstIndex(where: { $0.id == id }) else { return }
        removeCustomCover(for: stacks[index])
        stacks.remove(at: index)
        saveAndNotify()
    }

    func setCover(stackID: UUID, manga: MangaIdentifier) {
        guard let index = stacks.firstIndex(where: { $0.id == stackID }),
              stacks[index].members.contains(manga) else { return }
        removeCustomCover(for: stacks[index])
        stacks[index].customCoverFileName = nil
        stacks[index].coverManga = manga
        saveAndNotify()
    }

    func setCustomCover(stackID: UUID, image: UIImage) -> Bool {
        guard let index = stacks.firstIndex(where: { $0.id == stackID }),
              let data = preparedCover(image)?.jpegData(compressionQuality: 0.9) else { return false }
        Self.coversDirectory.createDirectory()
        removeCustomCover(for: stacks[index])
        let fileName = "\(stackID.uuidString)-\(UUID().uuidString).jpg"
        let url = Self.coversDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            stacks[index].customCoverFileName = fileName
            stacks[index].coverManga = nil
            saveAndNotify()
            return true
        } catch {
            return false
        }
    }

    func customCoverURL(for stack: LibraryStack) -> URL? {
        guard let fileName = stack.customCoverFileName else { return nil }
        let url = Self.coversDirectory.appendingPathComponent(fileName)
        return url.exists ? url : nil
    }

    func backupStacks() -> [BackupLibraryStack] {
        stacks.map { stack in
            BackupLibraryStack(
                id: stack.id,
                name: stack.name,
                dateCreated: stack.dateCreated,
                members: stack.members,
                coverManga: stack.coverManga,
                customCover: customCoverURL(for: stack).flatMap { try? Data(contentsOf: $0) }
            )
        }
    }

    func restore(_ backupStacks: [BackupLibraryStack], validManga: Set<MangaIdentifier>) {
        for stack in stacks { removeCustomCover(for: stack) }
        stacks = backupStacks.compactMap { backup in
            let members = backup.members.filter(validManga.contains)
            guard !members.isEmpty else { return nil }
            var fileName: String?
            if let customCover = backup.customCover {
                Self.coversDirectory.createDirectory()
                let candidate = "\(backup.id.uuidString)-\(UUID().uuidString).jpg"
                if (try? customCover.write(
                    to: Self.coversDirectory.appendingPathComponent(candidate),
                    options: .atomic
                )) != nil {
                    fileName = candidate
                }
            }
            return LibraryStack(
                id: backup.id,
                name: backup.name,
                dateCreated: backup.dateCreated,
                members: members,
                coverManga: backup.coverManga.flatMap { members.contains($0) ? $0 : nil } ?? members.first,
                customCoverFileName: fileName
            )
        }
        normalizeAndSaveIfNeeded(forceNotify: true)
    }

    func prune(validManga: Set<MangaIdentifier>) {
        var changed = false
        for index in stacks.indices.reversed() {
            let oldMembers = stacks[index].members
            stacks[index].members.removeAll { !validManga.contains($0) }
            changed = changed || oldMembers != stacks[index].members
            if stacks[index].members.isEmpty {
                removeCustomCover(for: stacks[index])
                stacks.remove(at: index)
                changed = true
            } else if let cover = stacks[index].coverManga, !stacks[index].members.contains(cover) {
                stacks[index].coverManga = stacks[index].members.first
                changed = true
            }
        }
        if changed { saveAndNotify() }
    }

    private func isNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        !stacks.contains {
            $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private func remove(
        _ manga: MangaIdentifier,
        deletingEmptyStack: Bool,
        notify: Bool
    ) {
        guard let index = stacks.firstIndex(where: { $0.members.contains(manga) }) else { return }
        stacks[index].members.removeAll { $0 == manga }
        if stacks[index].members.isEmpty, deletingEmptyStack {
            removeCustomCover(for: stacks[index])
            stacks.remove(at: index)
        } else if stacks[index].coverManga == manga {
            stacks[index].coverManga = stacks[index].members.first
        }
        if notify { saveAndNotify() }
    }

    private func normalizeAndSaveIfNeeded(forceNotify: Bool = false) {
        var seen = Set<MangaIdentifier>()
        var changed = false
        for index in stacks.indices.reversed() {
            let original = stacks[index].members
            stacks[index].members = original.filter { seen.insert($0).inserted }
            changed = changed || original != stacks[index].members
            if stacks[index].members.isEmpty {
                removeCustomCover(for: stacks[index])
                stacks.remove(at: index)
                changed = true
            } else if let cover = stacks[index].coverManga,
                      !stacks[index].members.contains(cover) {
                stacks[index].coverManga = stacks[index].members.first
                changed = true
            }
        }
        if changed || forceNotify { saveAndNotify() }
    }

    private func saveAndNotify() {
        Self.directory.createDirectory()
        if let data = try? JSONEncoder().encode(stacks) {
            try? data.write(to: Self.metadataURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    private func removeCustomCover(for stack: LibraryStack) {
        guard let fileName = stack.customCoverFileName else { return }
        try? FileManager.default.removeItem(at: Self.coversDirectory.appendingPathComponent(fileName))
    }

    private func preparedCover(_ image: UIImage) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let target = CGSize(width: 630, height: 945)
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2)
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }
}
