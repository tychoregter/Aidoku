//
//  CoreDataManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import CoreData

final class CoreDataManager: @unchecked Sendable {
    static let shared = CoreDataManager()

    let container: NSPersistentContainer

    @MainActor
    var context: NSManagedObjectContext {
        container.viewContext
    }

    private init() {
        self.container = Self.createContainer()
    }

    static func createContainer() -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Aidoku")

        let storeDirectory = FileManager.default.applicationSupportDirectory

        let primaryDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Aidoku.sqlite"))
        primaryDescription.configuration = "Cloud"
        primaryDescription.shouldMigrateStoreAutomatically = true
        primaryDescription.shouldInferMappingModelAutomatically = true

        primaryDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        let localDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Local.sqlite"))
        localDescription.configuration = "Local"
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true

        container.persistentStoreDescriptions = [
            primaryDescription,
            localDescription
        ]

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                LogManager.logger.error("Error loading persistent stores \(error), \(error.userInfo)")
            }
        }

        return container
    }

    @MainActor
    func save() {
        do {
            try context.save()
        } catch {
            LogManager.logger.error("CoreDataManager.save: \(error.localizedDescription)")
        }
    }

//    func saveIfNeeded() {
//        if context.hasChanges {
//            save()
//        }
//    }

    func remove(_ objectID: NSManagedObjectID) {
        container.performBackgroundTask { context in
            let object = context.object(with: objectID)
            context.delete(object)
            try? context.save()
        }
    }

    /// Clear all objects from fetch request.
    func clear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext) {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
        do {
            _ = try context.execute(deleteRequest)
        } catch {
            LogManager.logger.error("CoreDataManager.clear: \(error.localizedDescription)")
        }
    }

    func queueClear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext) {
        let objects = (try? context.fetch(request)) ?? []
        for object in objects {
            context.delete(object)
        }
    }

    // TODO: clean this up
    func migrateChapterHistory(progress: (@Sendable (Float) -> Void)? = nil) async {
        LogManager.logger.info("Beginning chapter history migration for 0.6")

        await container.performBackgroundTask { context in
            let request = HistoryObject.fetchRequest()
            let historyObjects = (try? context.fetch(request)) ?? []
            let total = Float(historyObjects.count)
            var i: Float = 0
            var count = 0
            for historyObject in historyObjects {
                progress?(i / total)
                i += 1
                guard
                    historyObject.chapter == nil,
                    let chapterObject = self.getChapter(
                        chapterId: historyObject.identifier,
                        context: context
                    )
                else { continue }
                historyObject.chapter = chapterObject
                count += 1
            }
            try? context.save()

            LogManager.logger.info("Migrated \(count)/\(historyObjects.count) history objects")
        }
    }
}

extension CoreDataManager {
    func deduplicate(objectIds: [NSManagedObjectID]) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        // Work in batches, saving and resetting in between.
        for batch in objectIds.chunked(into: 500) {
            context.performAndWait {
                for objectId in batch {
                    deduplicate(objectId: objectId, context: context)
                }
                do {
                    try context.save()
                } catch {
                    LogManager.logger.error("deduplicate: \(error.localizedDescription)")
                }
                context.reset()
            }
        }
    }

    func deduplicate(objectId: NSManagedObjectID, context: NSManagedObjectContext) {
        guard let object = try? context.existingObject(with: objectId) else { return }

        let request: NSFetchRequest<NSFetchRequestResult>?

        if let object = object as? MangaObject {
            request = MangaObject.fetchRequest()
            request?.predicate = NSPredicate(format: "sourceId == %@ AND id == %@", object.sourceId, object.id)
        } else if let object = object as? CategoryObject {
            request = CategoryObject.fetchRequest()
            request?.predicate = NSPredicate(format: "title == %@", object.title ?? "")
        } else if let object = object as? ChapterObject {
            request = ChapterObject.fetchRequest()
            request?.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND id == %@",
                object.sourceId, object.mangaId, object.id
            )
        } else if let object = object as? HistoryObject {
            request = HistoryObject.fetchRequest()
            request?.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND chapterId == %@",
                object.sourceId, object.mangaId, object.chapterId
            )
        } else if let object = object as? LibraryMangaObject {
            request = LibraryMangaObject.fetchRequest()
            request?.predicate = NSPredicate(
                format: "manga.sourceId == %@ AND manga.id == %@",
                object.manga?.sourceId ?? "", object.manga?.id ?? ""
            )
        } else if let object = object as? TrackObject {
            request = TrackObject.fetchRequest()
            request?.predicate = NSPredicate(format: "id == %@ AND trackerId == %@", object.id ?? "", object.trackerId ?? "")
        } else {
            request = nil
        }

        guard let request = request else { return }

        if (try? context.count(for: request)) ?? 0 > 1 {
            guard let objects = try? context.fetch(request) else { return }
            for object in objects.dropFirst(1) {
                if let object = object as? NSManagedObject {
                    context.delete(object)
                }
            }
        }
    }
}
