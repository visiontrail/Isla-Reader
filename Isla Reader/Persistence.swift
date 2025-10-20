//
//  Persistence.swift
//  Isla Reader
//
//  Created by 郭亮 on 2025/9/10.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for i in 0..<5 {
            let book = Book(context: viewContext)
            book.id = UUID()
            book.title = "示例书籍 \(i+1)"
            book.author = "作者 \(i+1)"
            book.language = "zh-CN"
            book.filePath = "/dev/null"
            book.fileFormat = "txt"
            book.fileSize = 0
            book.checksum = UUID().uuidString
            book.totalPages = 100
            book.createdAt = Date()
            book.updatedAt = Date()

            let item = LibraryItem(context: viewContext)
            item.id = UUID()
            item.statusRaw = ReadingStatus.wantToRead.rawValue
            item.isFavorite = false
            item.rating = 0
            item.addedAt = Date()
            item.lastAccessedAt = Date()
            item.sortOrder = Int32(i)
            item.book = book
            book.libraryItem = item
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Isla_Reader")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
