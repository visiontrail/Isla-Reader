//
//  Highlight.swift
//  LanRead
//
//  Created by 郭亮 on 2025/9/10.
//

import Foundation
import CoreData
import SwiftUI

@objc(Highlight)
public class Highlight: NSManagedObject {
    
}

private struct HighlightSelectionAnchor: Codable {
    let chapterIndex: Int
    let pageIndex: Int
    let offset: Int?
}

extension Highlight {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Highlight> {
        return NSFetchRequest<Highlight>(entityName: "Highlight")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var selectedText: String
    @NSManaged public var startPosition: String // JSON string for position
    @NSManaged public var endPosition: String // JSON string for position
    @NSManaged public var chapter: String?
    @NSManaged public var pageNumber: Int32
    @NSManaged public var colorHex: String // Highlight color
    @NSManaged public var note: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    
    // Relationship
    @NSManaged public var book: Book
    
}

extension Highlight: Identifiable {
    
    var highlightColor: Color {
        return Color(hex: colorHex) ?? .yellow
    }
    
    var hasNote: Bool {
        return note?.isEmpty == false
    }
    
    var displayText: String {
        return selectedText
    }

    var readingLocation: BookmarkLocation? {
        guard let data = startPosition.data(using: .utf8) else { return nil }

        if let anchor = try? JSONDecoder().decode(HighlightSelectionAnchor.self, from: data) {
            return BookmarkLocation(
                chapterIndex: max(anchor.chapterIndex, 0),
                pageIndex: max(anchor.pageIndex, 0),
                chapterTitle: chapter
            )
        }

        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let chapterValue = payload["chapterIndex"] as? NSNumber,
           let pageValue = payload["pageIndex"] as? NSNumber {
            return BookmarkLocation(
                chapterIndex: max(chapterValue.intValue, 0),
                pageIndex: max(pageValue.intValue, 0),
                chapterTitle: chapter
            )
        }

        return nil
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    var hexString: String {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return "FFFF00" // Default to yellow
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}
