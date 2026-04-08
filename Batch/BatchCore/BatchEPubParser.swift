import BatchModels
import BatchSupport
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct BatchEPubParser {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func parseBook(at epubPath: String) throws -> BatchBook {
        let epubURL = URL(fileURLWithPath: epubPath)
        guard fileManager.fileExists(atPath: epubURL.path) else {
            throw BatchError.fileNotFound(epubPath)
        }

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("lanread-batch-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        try unzip(epubURL: epubURL, to: tempDirectory)

        let rootFilePath = try parseContainerRootFile(in: tempDirectory)
        let opfURL = tempDirectory.appendingPathComponent(rootFilePath)
        let opf = try parseOPF(at: opfURL)

        let opfBaseDirectory = opfURL.deletingLastPathComponent()
        var chapters: [BatchBookChapter] = []
        chapters.reserveCapacity(opf.spineItemIDs.count)

        for (index, itemID) in opf.spineItemIDs.enumerated() {
            guard let href = opf.manifest[itemID] else { continue }
            let hrefWithoutFragment = href.components(separatedBy: "#").first ?? href
            let decodedHref = hrefWithoutFragment.removingPercentEncoding ?? hrefWithoutFragment
            let chapterURL = opfBaseDirectory.appendingPathComponent(decodedHref)

            guard fileManager.fileExists(atPath: chapterURL.path) else { continue }
            let chapterData = try Data(contentsOf: chapterURL)
            guard let chapterHTML = Self.decodeText(chapterData) else { continue }

            let chapterTitle = extractChapterTitle(fromHTML: chapterHTML, fallbackHref: decodedHref)
            let chapterText = extractReadableText(fromHTML: chapterHTML)
            guard chapterText.count >= 120 else { continue }

            let chapter = BatchBookChapter(
                title: chapterTitle,
                content: chapterText,
                order: index + 1,
                sourceHref: decodedHref
            )

            if isLikelyNonBodyChapter(chapter) {
                continue
            }
            chapters.append(chapter)
        }

        if chapters.isEmpty {
            throw BatchError.runtime("No readable body chapters found in EPUB.")
        }

        let metadata = BatchBookMetadata(
            title: opf.title ?? epubURL.deletingPathExtension().lastPathComponent,
            author: opf.author,
            language: opf.language,
            coverImageData: extractCoverImage(opf: opf, relativeTo: opfBaseDirectory)
        )

        return BatchBook(metadata: metadata, chapters: chapters)
    }

    private func unzip(epubURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", epubURL.path, "-d", destinationURL.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BatchError.runtime("Failed to start unzip process: \(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let details = stderrText?.isEmpty == false ? stderrText! : "unknown unzip error"
            throw BatchError.runtime("Failed to unzip EPUB: \(details)")
        }
    }

    private func parseContainerRootFile(in extractedRoot: URL) throws -> String {
        let containerURL = extractedRoot.appendingPathComponent("META-INF/container.xml")
        guard fileManager.fileExists(atPath: containerURL.path) else {
            throw BatchError.runtime("EPUB container.xml not found.")
        }

        let data = try Data(contentsOf: containerURL)
        guard let xml = Self.decodeText(data) else {
            throw BatchError.runtime("Cannot decode container.xml.")
        }

        if let rootPath = Self.firstCapture(
            in: xml,
            pattern: #"full-path\s*=\s*["']([^"']+)["']"#,
            group: 1
        ) {
            return rootPath
        }

        throw BatchError.runtime("Cannot locate OPF rootfile path in container.xml.")
    }

    private func parseOPF(at opfURL: URL) throws -> ParsedOPF {
        let opfData = try Data(contentsOf: opfURL)
        let delegate = OPFXMLDelegate()
        let parser = XMLParser(data: opfData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.parse()

        let parsed = delegate.toParsedOPF()
        guard !parsed.manifest.isEmpty, !parsed.spineItemIDs.isEmpty else {
            throw BatchError.runtime("Failed to parse EPUB manifest/spine from OPF.")
        }
        return parsed
    }

    private func extractChapterTitle(fromHTML html: String, fallbackHref: String) -> String {
        if let h1 = Self.firstCapture(in: html, pattern: #"(?is)<h1[^>]*>(.*?)</h1>"#, group: 1) {
            let cleaned = Self.cleanInlineHTML(h1)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        if let titleTag = Self.firstCapture(in: html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#, group: 1) {
            let cleaned = Self.cleanInlineHTML(titleTag)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        let fallbackName = URL(fileURLWithPath: fallbackHref).deletingPathExtension().lastPathComponent
        let trimmed = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Chapter" : trimmed
    }

    private func extractReadableText(fromHTML html: String) -> String {
        var content = html
        content = Self.replacing(content, pattern: #"(?is)<script\b[^>]*>.*?</script>"#, with: " ")
        content = Self.replacing(content, pattern: #"(?is)<style\b[^>]*>.*?</style>"#, with: " ")
        content = Self.replacing(
            content,
            pattern: #"(?is)</?(p|div|h[1-6]|li|blockquote|section|article|br|tr|td|th)\b[^>]*>"#,
            with: "\n"
        )
        content = Self.replacing(content, pattern: #"(?is)<[^>]+>"#, with: " ")

        content = Self.decodeHTMLEntities(in: content)
        content = Self.replacing(content, pattern: #"[ \t\u{00A0}]+"#, with: " ")
        content = Self.replacing(content, pattern: #"\n{3,}"#, with: "\n\n")

        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }

    private func isLikelyNonBodyChapter(_ chapter: BatchBookChapter) -> Bool {
        let title = chapter.title.lowercased()
        let href = chapter.sourceHref?.lowercased() ?? ""
        let reference = "\(title) \(href)"

        let markers = [
            "cover",
            "toc",
            "contents",
            "copyright",
            "titlepage",
            "imprint",
            "about",
            "acknowledg",
            "nav"
        ]

        let hasMarker = markers.contains { reference.contains($0) }
        return hasMarker && chapter.content.count < 3_500
    }

    private static func decodeText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        if let utf16LE = String(data: data, encoding: .utf16LittleEndian) {
            return utf16LE
        }
        if let utf16BE = String(data: data, encoding: .utf16BigEndian) {
            return utf16BE
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return nil
    }

    private static func firstCapture(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let captureRange = Range(match.range(at: group), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func replacing(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func decodeHTMLEntities(in text: String) -> String {
        var decoded = text
        let mappings: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'")
        ]
        for (entity, replacement) in mappings {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decoded
    }

    private static func cleanInlineHTML(_ text: String) -> String {
        let stripped = replacing(text, pattern: #"(?is)<[^>]+>"#, with: " ")
        let decoded = decodeHTMLEntities(in: stripped)
        let squashed = replacing(decoded, pattern: #"[ \t\n\r]+"#, with: " ")
        return squashed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ParsedOPF {
    var title: String?
    var author: String?
    var language: String?
    var coverID: String?
    var coverHref: String?
    var manifestItems: [String: ParsedOPFManifestItem]
    var manifest: [String: String]
    var spineItemIDs: [String]
}

private struct ParsedOPFManifestItem {
    var href: String
    var mediaType: String?
    var properties: Set<String>
}

private final class OPFXMLDelegate: NSObject, XMLParserDelegate {
    private var currentCapture: CaptureField?
    private var currentText = ""
    private var currentMetaProperty: String?
    private var currentMetaRefines: String?

    private(set) var title: String?
    private(set) var author: String?
    private(set) var language: String?
    private(set) var coverID: String?
    private(set) var coverHref: String?
    private(set) var manifest: [String: String] = [:]
    private(set) var manifestItems: [String: ParsedOPFManifestItem] = [:]
    private(set) var spineItemIDs: [String] = []

    enum CaptureField {
        case title
        case author
        case language
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        currentText = ""
        let localName = Self.localName(of: elementName)

        if localName == "item",
           let id = firstAttributeValue(named: "id", in: attributeDict),
           let href = firstAttributeValue(named: "href", in: attributeDict),
           !id.isEmpty,
           !href.isEmpty {
            manifest[id] = href
            let mediaType = firstAttributeValue(named: "media-type", in: attributeDict)?.lowercased()
            let properties = tokenizedProperties(firstAttributeValue(named: "properties", in: attributeDict))
            manifestItems[id] = ParsedOPFManifestItem(
                href: href,
                mediaType: mediaType,
                properties: properties
            )
            if properties.contains("cover-image") {
                if coverID == nil {
                    coverID = id
                }
                if coverHref == nil {
                    coverHref = href
                }
            }
            return
        }

        if localName == "itemref",
           let idRef = firstAttributeValue(named: "idref", in: attributeDict),
           !idRef.isEmpty {
            if let linear = firstAttributeValue(named: "linear", in: attributeDict),
               linear.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no" {
                return
            }
            spineItemIDs.append(idRef)
            return
        }

        if localName == "meta" {
            if let coverName = firstAttributeValue(named: "name", in: attributeDict)?.lowercased(),
               coverName == "cover",
               let content = firstAttributeValue(named: "content", in: attributeDict),
               !content.isEmpty {
                coverID = Self.normalizeManifestIdentifier(content)
            }

            if let property = firstAttributeValue(named: "property", in: attributeDict)?.lowercased() {
                currentMetaProperty = property
                currentMetaRefines = firstAttributeValue(named: "refines", in: attributeDict)

                if property == "cover-image",
                   let content = firstAttributeValue(named: "content", in: attributeDict),
                   !content.isEmpty {
                    coverID = Self.normalizeManifestIdentifier(content)
                }
            } else {
                currentMetaProperty = nil
                currentMetaRefines = nil
            }
            return
        }

        switch localName {
        case "title":
            currentCapture = .title
        case "creator":
            currentCapture = .author
        case "language":
            currentCapture = .language
        default:
            currentCapture = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentCapture != nil else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = Self.localName(of: elementName)
        if localName == "meta" {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentMetaProperty == "cover-image" {
                if coverID == nil, let normalized = Self.normalizeManifestIdentifier(text) {
                    coverID = normalized
                }
                if coverID == nil, let currentMetaRefines {
                    coverID = Self.normalizeManifestIdentifier(currentMetaRefines)
                }
            }
            currentMetaProperty = nil
            currentMetaRefines = nil
            currentText = ""
            return
        }

        guard let capture = currentCapture else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            currentCapture = nil
            currentText = ""
            return
        }

        switch capture {
        case .title:
            if title == nil {
                title = text
            }
        case .author:
            if author == nil {
                author = text
            }
        case .language:
            if language == nil {
                language = text
            }
        }

        currentCapture = nil
        currentText = ""
    }

    func toParsedOPF() -> ParsedOPF {
        let resolvedCoverHref: String?
        if let coverHref {
            resolvedCoverHref = coverHref
        } else if let coverID {
            resolvedCoverHref = manifest[coverID]
        } else {
            resolvedCoverHref = nil
        }

        return ParsedOPF(
            title: title,
            author: author,
            language: language,
            coverID: coverID,
            coverHref: resolvedCoverHref,
            manifestItems: manifestItems,
            manifest: manifest,
            spineItemIDs: spineItemIDs
        )
    }

    private static func localName(of elementName: String) -> String {
        guard let index = elementName.lastIndex(of: ":") else {
            return elementName.lowercased()
        }
        let next = elementName.index(after: index)
        return String(elementName[next...]).lowercased()
    }

    private func firstAttributeValue(named targetName: String, in attributes: [String: String]) -> String? {
        for (name, value) in attributes {
            let localName = Self.localName(of: name)
            if localName == targetName {
                return value
            }
        }
        return nil
    }

    private func tokenizedProperties(_ value: String?) -> Set<String> {
        guard let value else {
            return []
        }
        return Set(
            value.split(whereSeparator: \.isWhitespace)
                .map { $0.lowercased() }
        )
    }

    private static func normalizeManifestIdentifier(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var normalized = trimmed
        while normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        return normalized.isEmpty ? nil : normalized
    }
}

private extension BatchEPubParser {
    func extractCoverImage(opf: ParsedOPF, relativeTo baseURL: URL) -> Data? {
        if let coverID = opf.coverID,
           let href = opf.manifest[coverID] {
            let coverURL = resolveRelativePathURL(href, relativeTo: baseURL)
            if let data = try? Data(contentsOf: coverURL) {
                return data
            }
        }

        if let coverHref = opf.coverHref {
            let coverURL = resolveRelativePathURL(coverHref, relativeTo: baseURL)
            if let data = try? Data(contentsOf: coverURL) {
                return data
            }
        }

        for item in opf.manifestItems.values where isLikelyImage(item) {
            let imageURL = resolveRelativePathURL(item.href, relativeTo: baseURL)
            if let data = try? Data(contentsOf: imageURL) {
                return data
            }
        }

        return nil
    }

    func isLikelyImage(_ item: ParsedOPFManifestItem) -> Bool {
        if let mediaType = item.mediaType?.lowercased(),
           mediaType.hasPrefix("image/") {
            return true
        }

        let href = item.href.lowercased()
        return href.hasSuffix(".jpg")
            || href.hasSuffix(".jpeg")
            || href.hasSuffix(".png")
            || href.hasSuffix(".gif")
            || href.hasSuffix(".webp")
    }

    func resolveRelativePathURL(_ href: String, relativeTo baseURL: URL) -> URL {
        let withoutFragment = href.components(separatedBy: "#").first ?? href
        let withoutQuery = withoutFragment.components(separatedBy: "?").first ?? withoutFragment
        let decodedPath = withoutQuery.removingPercentEncoding ?? withoutQuery

        if let absolute = URL(string: decodedPath), absolute.isFileURL {
            return absolute.standardizedFileURL
        }
        if let relative = URL(string: decodedPath, relativeTo: baseURL) {
            return relative.standardizedFileURL
        }
        return baseURL.appendingPathComponent(decodedPath).standardizedFileURL
    }
}
