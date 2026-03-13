//
//  CoreDataModelDeleteRuleTests.swift
//  LanReadTests
//

import CoreData
import Foundation
import Testing
@testable import LanRead

struct CoreDataModelDeleteRuleTests {
    @Test
    @MainActor
    func compiledModelUsesExpectedDeleteRules() throws {
        let model = PersistenceController(inMemory: true).container.managedObjectModel

        #expect(try relationship(named: "book", on: "LibraryItem", in: model).deleteRule == .nullifyDeleteRule)

        #expect(try relationship(named: "readingProgress", on: "Book", in: model).deleteRule == .cascadeDeleteRule)
        #expect(try relationship(named: "bookmarks", on: "Book", in: model).deleteRule == .cascadeDeleteRule)
        #expect(try relationship(named: "highlights", on: "Book", in: model).deleteRule == .cascadeDeleteRule)
        #expect(try relationship(named: "annotations", on: "Book", in: model).deleteRule == .cascadeDeleteRule)
        #expect(try relationship(named: "libraryItem", on: "Book", in: model).deleteRule == .cascadeDeleteRule)

        #expect(try relationship(named: "book", on: "Bookmark", in: model).deleteRule == .nullifyDeleteRule)
        #expect(try relationship(named: "book", on: "Highlight", in: model).deleteRule == .nullifyDeleteRule)
        #expect(try relationship(named: "book", on: "Annotation", in: model).deleteRule == .nullifyDeleteRule)
        #expect(try relationship(named: "book", on: "ReadingProgress", in: model).deleteRule == .nullifyDeleteRule)
    }

    @Test
    @MainActor
    func deletingChildKeepsBookAndDeletingBookCascadesDependents() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext

        let book = makeBook(context: context)
        _ = makeLibraryItem(book: book, context: context)
        _ = makeReadingProgress(book: book, context: context)
        let bookmark = makeBookmark(book: book, context: context)
        _ = makeHighlight(book: book, context: context)
        _ = makeAnnotation(book: book, context: context)

        try context.save()

        context.delete(bookmark)
        try context.save()

        #expect(try fetchCount(Book.self, in: context) == 1)
        #expect(try fetchCount(Bookmark.self, in: context) == 0)
        #expect(try fetchCount(Highlight.self, in: context) == 1)
        #expect(try fetchCount(Annotation.self, in: context) == 1)
        #expect(try fetchCount(ReadingProgress.self, in: context) == 1)
        #expect(try fetchCount(LibraryItem.self, in: context) == 1)

        context.delete(book)
        try context.save()

        #expect(try fetchCount(Book.self, in: context) == 0)
        #expect(try fetchCount(LibraryItem.self, in: context) == 0)
        #expect(try fetchCount(ReadingProgress.self, in: context) == 0)
        #expect(try fetchCount(Highlight.self, in: context) == 0)
        #expect(try fetchCount(Annotation.self, in: context) == 0)
    }
}

private extension CoreDataModelDeleteRuleTests {
    enum TestError: Error {
        case missingEntity(String)
        case missingRelationship(entity: String, relationship: String)
    }

    func relationship(
        named relationshipName: String,
        on entityName: String,
        in model: NSManagedObjectModel
    ) throws -> NSRelationshipDescription {
        guard let entity = model.entitiesByName[entityName] else {
            throw TestError.missingEntity(entityName)
        }
        guard let relationship = entity.relationshipsByName[relationshipName] else {
            throw TestError.missingRelationship(entity: entityName, relationship: relationshipName)
        }
        return relationship
    }

    func fetchCount<T: NSManagedObject>(
        _ type: T.Type,
        in context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        return try context.count(for: request)
    }

    func makeBook(context: NSManagedObjectContext) -> Book {
        let book = Book(context: context)
        book.id = UUID()
        book.title = "Delete Rules"
        book.author = "LanRead"
        book.language = "en"
        book.filePath = UUID().uuidString + ".epub"
        book.fileFormat = "epub"
        book.fileSize = 1
        book.checksum = UUID().uuidString
        book.totalPages = 12
        book.createdAt = Date()
        book.updatedAt = Date()
        return book
    }

    func makeLibraryItem(book: Book, context: NSManagedObjectContext) -> LibraryItem {
        let item = LibraryItem(context: context)
        item.id = UUID()
        item.statusRaw = ReadingStatus.wantToRead.rawValue
        item.isFavorite = false
        item.rating = 0
        item.addedAt = Date()
        item.lastAccessedAt = Date()
        item.sortOrder = 0
        item.book = book
        return item
    }

    func makeReadingProgress(book: Book, context: NSManagedObjectContext) -> ReadingProgress {
        let progress = ReadingProgress(context: context)
        progress.id = UUID()
        progress.currentPage = 1
        progress.currentChapter = "Chapter 1"
        progress.currentPosition = "{\"chapterIndex\":0,\"pageIndex\":0}"
        progress.progressPercentage = 0.1
        progress.lastReadAt = Date()
        progress.totalReadingTime = 60
        progress.createdAt = Date()
        progress.updatedAt = Date()
        progress.book = book
        return progress
    }

    func makeBookmark(book: Book, context: NSManagedObjectContext) -> Bookmark {
        let bookmark = Bookmark(context: context)
        bookmark.id = UUID()
        bookmark.chapterIndex = 0
        bookmark.pageIndex = 0
        bookmark.chapterTitle = "Chapter 1"
        bookmark.createdAt = Date()
        bookmark.colorHex = Bookmark.defaultColorHex
        bookmark.book = book
        return bookmark
    }

    func makeHighlight(book: Book, context: NSManagedObjectContext) -> Highlight {
        let highlight = Highlight(context: context)
        highlight.id = UUID()
        highlight.selectedText = "Highlighted text"
        highlight.startPosition = "{\"chapterIndex\":0,\"pageIndex\":0}"
        highlight.endPosition = "{\"chapterIndex\":0,\"pageIndex\":1}"
        highlight.chapter = "Chapter 1"
        highlight.pageNumber = 0
        highlight.colorHex = "FFFF00"
        highlight.createdAt = Date()
        highlight.updatedAt = Date()
        highlight.book = book
        return highlight
    }

    func makeAnnotation(book: Book, context: NSManagedObjectContext) -> Annotation {
        let annotation = Annotation(context: context)
        annotation.id = UUID()
        annotation.content = "Annotation"
        annotation.position = "{\"chapterIndex\":0,\"pageIndex\":0}"
        annotation.chapter = "Chapter 1"
        annotation.pageNumber = 0
        annotation.associatedText = "Highlighted text"
        annotation.createdAt = Date()
        annotation.updatedAt = Date()
        annotation.book = book
        return annotation
    }
}
