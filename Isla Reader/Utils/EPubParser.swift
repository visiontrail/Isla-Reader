//
//  EPubParser.swift
//  LanRead
//
//  Created by AI Assistant on 2025/1/20.
//

import Foundation
import CoreData
import zlib

struct EPubMetadata {
    let title: String
    let author: String?
    let language: String?
    let coverImageData: Data?
    let chapters: [Chapter]
    let tocItems: [TOCItem]
    let totalPages: Int
    let resourcesBaseURL: URL? // 资源文件的基础URL
}

struct Chapter {
    let title: String
    let content: String
    let htmlContent: String // 保留原始HTML内容，已处理图片
    let order: Int
}

struct TOCItem {
    let title: String
    let href: String
    let level: Int
    let chapterIndex: Int

    var fragment: String? {
        let components = href.components(separatedBy: "#")
        guard components.count > 1 else { return nil }
        let rawFragment = components.dropFirst().joined(separator: "#").trimmingCharacters(in: .whitespacesAndNewlines)
        return rawFragment.isEmpty ? nil : rawFragment
    }
}

struct OPFInfo {
    struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String?
        let properties: Set<String>
    }

    var title: String?
    var author: String?
    var language: String?
    var coverId: String?
    var manifestMap: [String: String] = [:]
    var manifestItems: [String: ManifestItem] = [:]
    var spineItems: [String] = []
    var tocId: String? // NCX file ID
    var navId: String? // EPUB 3 nav document ID
    var coverHref: String? // direct cover href fallback
    var tocCandidateIds: [String] = [] // ordered TOC fallback candidates
}

struct TOCEntry {
    let title: String
    let href: String
    let order: Int
    let level: Int
}

class EPubParser {
    private struct ParsedFileFingerprint: Hashable {
        let path: String
        let size: Int64
        let modifiedAt: TimeInterval
    }

    private struct CachedMetadataEntry {
        let metadata: EPubMetadata
    }

    private static let cacheLock = NSLock()
    private static var metadataCache: [ParsedFileFingerprint: CachedMetadataEntry] = [:]
    private static var metadataCacheOrder: [ParsedFileFingerprint] = []
    private static let metadataCacheLimit = 2

    private static let verboseTOCEntryLoggingEnabled =
        ProcessInfo.processInfo.environment["LANREAD_VERBOSE_TOC_LOGS"] == "1"
    private static let tocEntryInitialDetailedCount = 3
    private static let tocEntryProgressInterval = 50
    
    static func parseEPub(from url: URL) throws -> EPubMetadata {
        DebugLogger.info("EPubParser: 开始解析ePub文件")
        DebugLogger.info("EPubParser: 文件URL: \(url.absoluteString)")
        DebugLogger.info("EPubParser: 文件路径: \(url.path)")
        
        // 检查文件是否存在
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            DebugLogger.error("EPubParser: 文件不存在: \(url.path)")
            throw EPubParseError.fileNotFound
        }
        
        // 检查文件是否可读
        guard fileManager.isReadableFile(atPath: url.path) else {
            DebugLogger.error("EPubParser: 文件不可读: \(url.path)")
            throw EPubParseError.fileNotFound
        }
        
        let fileFingerprint = makeFileFingerprint(for: url, fileManager: fileManager)
        if let fileFingerprint {
            DebugLogger.info("EPubParser: 文件大小: \(fileFingerprint.size) bytes")
            if let cachedMetadata = cachedMetadata(for: fileFingerprint) {
                DebugLogger.info(
                    "EPubParser: 命中内存缓存，章节=\(cachedMetadata.chapters.count), toc=\(cachedMetadata.tocItems.count)"
                )
                return cachedMetadata
            }
        } else {
            DebugLogger.warning("EPubParser: 无法获取文件属性，将跳过解析缓存")
        }
        
        // 创建临时解压目录
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        DebugLogger.info("EPubParser: 创建临时目录: \(tempDir.path)")
        
        defer {
            // 清理临时目录
            try? fileManager.removeItem(at: tempDir)
            DebugLogger.info("EPubParser: 清理临时目录")
        }
        
        do {
            // 解压 EPUB 文件
            DebugLogger.info("EPubParser: 开始解压EPUB文件")
            try unzipEPub(from: url, to: tempDir)
            DebugLogger.success("EPubParser: EPUB文件解压成功")
            
            // 解析 container.xml 获取 OPF 文件路径
            let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
            guard fileManager.fileExists(atPath: containerPath.path) else {
                DebugLogger.error("EPubParser: 未找到container.xml文件")
                throw EPubParseError.invalidContainer
            }
            
            let containerData = try Data(contentsOf: containerPath)
            guard let rootfilePath = parseContainerXML(containerData) else {
                DebugLogger.error("EPubParser: 无法从container.xml中获取OPF文件路径")
                throw EPubParseError.invalidContainer
            }
            
            DebugLogger.info("EPubParser: OPF文件路径: \(rootfilePath)")
            
            // 解析 OPF 文件
            let opfPath = tempDir.appendingPathComponent(rootfilePath)
            let opfBaseURL = opfPath.deletingLastPathComponent()
            
            let opfData = try Data(contentsOf: opfPath)
            let opfInfo = parseOPFFile(opfData)
            
            // 提取元数据
            let title = opfInfo.title ?? url.lastPathComponent.replacingOccurrences(of: ".epub", with: "")
            let author = opfInfo.author
            let language = opfInfo.language
            
            DebugLogger.info("EPubParser: 标题: \(title)")
            DebugLogger.info("EPubParser: 作者: \(author ?? "未知")")
            DebugLogger.info("EPubParser: 语言: \(language ?? "未知")")
            
            // 解析目录（TOC）
            let tocEntries = parseTOC(opfInfo: opfInfo, baseURL: opfBaseURL, coverId: opfInfo.coverId)
            DebugLogger.info("EPubParser: 从TOC解析了 \(tocEntries.count) 个标题（含层级）")
            
            // 解析章节
            let chapterResult = try parseChapters(spineItems: opfInfo.spineItems, manifestMap: opfInfo.manifestMap, baseURL: opfBaseURL, tocEntries: tocEntries, coverId: opfInfo.coverId)
            let chapters = chapterResult.chapters
            DebugLogger.success("EPubParser: 成功解析 \(chapters.count) 个章节")
            
            // 将 TOC 映射到章节索引，保留层级
            let tocItems = mapTOCEntriesToChapters(tocEntries, hrefToChapterIndex: chapterResult.hrefToChapterIndex)
            
            // 提取封面图片（如果存在）
            let coverImageData = extractCoverImage(
                coverId: opfInfo.coverId,
                coverHref: opfInfo.coverHref,
                manifestMap: opfInfo.manifestMap,
                baseURL: opfBaseURL
            )
            
            let metadata = EPubMetadata(
                title: title,
                author: author,
                language: language,
                coverImageData: coverImageData,
                chapters: chapters,
                tocItems: tocItems,
                totalPages: chapters.count * 10, // 粗略估计
                resourcesBaseURL: nil // 图片已嵌入HTML，不需要baseURL
            )

            if let fileFingerprint {
                storeMetadataInCache(metadata, for: fileFingerprint)
            }
            DebugLogger.success("EPubParser: ePub解析完成")
            return metadata
            
        } catch {
            DebugLogger.error("EPubParser: 解析失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - ZIP解压
    
    private static func unzipEPub(from sourceURL: URL, to destinationURL: URL) throws {
        // 使用 Apple 的 NSFileManager 解压（通过 coordinateReadingItemAtURL）
        // 或者使用简单的 ZIP 读取实现
        
        // 尝试使用 Apple Archive framework (iOS 15+)
        if #available(iOS 15.0, *) {
            // 读取 ZIP 文件数据
            let zipData = try Data(contentsOf: sourceURL)
            
            // 使用 minizip 风格的简单解压
            try unzipData(zipData, to: destinationURL)
        } else {
            throw EPubParseError.unsupportedFormat
        }
    }
    
    // 简单的 ZIP 解压实现（使用手动解析 ZIP 格式）
    private static func unzipData(_ data: Data, to destinationURL: URL) throws {
        
        // ZIP 文件格式说明：
        // - 每个文件条目都有一个 Local File Header
        // - 文件内容跟随其后
        // - 文件末尾有 Central Directory
        
        // 为了简化，我们使用一个替代方案：
        // 1. 将 EPUB 文件复制到临时位置并重命名为 .zip
        // 2. 使用 Data(contentsOf:) 读取并手动解析
        
        // 实际上，最简单的方法是使用 libzip 或者直接读取 ZIP 内容
        // 但由于这个比较复杂，我们采用一个更实用的方法：
        
        // 创建一个简化的实现，直接读取 ZIP 中心目录
        try parseAndExtractZIP(data: data, to: destinationURL)
    }
    
    private struct ZIPCentralDirectoryEntry {
        let fileName: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let generalPurposeFlag: UInt16
        let localHeaderOffset: Int
    }

    private static func parseAndExtractZIP(data: Data, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard let entries = parseCentralDirectoryEntries(from: data), !entries.isEmpty else {
            throw EPubParseError.unsupportedFormat
        }

        for entry in entries {
            let normalizedPath = normalizedRelativeArchivePath(entry.fileName)
            guard let normalizedPath else {
                DebugLogger.warning("EPubParser: 跳过可疑ZIP条目路径: \(entry.fileName)")
                continue
            }

            guard let outputURL = resolveArchiveDestinationURL(
                archivePath: normalizedPath,
                destinationRoot: destinationURL
            ) else {
                DebugLogger.warning("EPubParser: 跳过越界ZIP条目: \(entry.fileName)")
                continue
            }

            if normalizedPath.hasSuffix("/") {
                try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
                continue
            }

            let outputDirectory = outputURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let payload = try extractCompressedPayload(for: entry, from: data)
            let extracted = try decompressZIPPayload(
                payload,
                method: entry.compressionMethod,
                expectedSize: entry.uncompressedSize,
                generalPurposeFlag: entry.generalPurposeFlag
            )
            try extracted.write(to: outputURL)
        }
    }

    private static func parseCentralDirectoryEntries(from data: Data) -> [ZIPCentralDirectoryEntry]? {
        guard let endOfCentralDirectoryOffset = findEndOfCentralDirectoryOffset(in: data) else {
            return nil
        }
        guard endOfCentralDirectoryOffset + 22 <= data.count else {
            return nil
        }
        guard data.readUInt32(at: endOfCentralDirectoryOffset) == 0x06054b50 else {
            return nil
        }

        let entryCount = Int(data.readUInt16(at: endOfCentralDirectoryOffset + 10))
        let centralDirectorySize = Int(data.readUInt32(at: endOfCentralDirectoryOffset + 12))
        let centralDirectoryOffset = Int(data.readUInt32(at: endOfCentralDirectoryOffset + 16))

        guard entryCount > 0 else {
            return []
        }
        guard centralDirectoryOffset >= 0, centralDirectorySize >= 0,
              centralDirectoryOffset + centralDirectorySize <= data.count else {
            return nil
        }

        var entries: [ZIPCentralDirectoryEntry] = []
        var cursor = centralDirectoryOffset
        let centralDirectoryEnd = centralDirectoryOffset + centralDirectorySize

        while cursor + 46 <= centralDirectoryEnd, entries.count < entryCount {
            guard data.readUInt32(at: cursor) == 0x02014b50 else {
                return nil
            }

            let generalPurposeFlag = data.readUInt16(at: cursor + 8)
            let compressionMethod = data.readUInt16(at: cursor + 10)
            let compressedSize = Int(data.readUInt32(at: cursor + 20))
            let uncompressedSize = Int(data.readUInt32(at: cursor + 24))
            let fileNameLength = Int(data.readUInt16(at: cursor + 28))
            let extraFieldLength = Int(data.readUInt16(at: cursor + 30))
            let commentLength = Int(data.readUInt16(at: cursor + 32))
            let localHeaderOffset = Int(data.readUInt32(at: cursor + 42))

            let recordLength = 46 + fileNameLength + extraFieldLength + commentLength
            guard cursor + recordLength <= data.count else {
                return nil
            }

            let fileNameStart = cursor + 46
            let fileNameEnd = fileNameStart + fileNameLength
            let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
            let isUTF8FileName = (generalPurposeFlag & (1 << 11)) != 0
            guard let fileName = decodeZIPFileName(fileNameData, utf8Flag: isUTF8FileName), !fileName.isEmpty else {
                cursor += recordLength
                continue
            }

            entries.append(
                ZIPCentralDirectoryEntry(
                    fileName: fileName,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    generalPurposeFlag: generalPurposeFlag,
                    localHeaderOffset: localHeaderOffset
                )
            )
            cursor += recordLength
        }

        return entries
    }

    private static func findEndOfCentralDirectoryOffset(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        // EOCD 之后最多有 65,535 字节注释 + 22 字节固定头
        let maxTail = min(data.count, 22 + 65_535)
        let start = data.count - maxTail
        var cursor = data.count - 22

        while cursor >= start {
            if data.readUInt32(at: cursor) == 0x06054b50 {
                return cursor
            }
            cursor -= 1
        }
        return nil
    }

    private static func decodeZIPFileName(_ data: Data, utf8Flag: Bool) -> String? {
        if utf8Flag {
            return String(data: data, encoding: .utf8)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func normalizedRelativeArchivePath(_ rawPath: String) -> String? {
        let slashNormalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard !slashNormalized.hasPrefix("/") else {
            return nil
        }

        let components = slashNormalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty else {
            return nil
        }

        var sanitized: [String] = []
        for component in components {
            if component == "." {
                continue
            }
            if component == ".." {
                return nil
            }
            sanitized.append(String(component))
        }

        var normalized = sanitized.joined(separator: "/")
        if rawPath.hasSuffix("/") {
            normalized += "/"
        }
        return normalized
    }

    private static func resolveArchiveDestinationURL(archivePath: String, destinationRoot: URL) -> URL? {
        let candidate = destinationRoot.appendingPathComponent(archivePath).standardizedFileURL
        let rootPath = destinationRoot.standardizedFileURL.path
        let candidatePath = candidate.path
        if candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") {
            return candidate
        }
        return nil
    }

    private static func extractCompressedPayload(for entry: ZIPCentralDirectoryEntry, from data: Data) throws -> Data {
        let localHeaderOffset = entry.localHeaderOffset
        guard localHeaderOffset >= 0, localHeaderOffset + 30 <= data.count else {
            throw EPubParseError.unsupportedFormat
        }
        guard data.readUInt32(at: localHeaderOffset) == 0x04034b50 else {
            throw EPubParseError.unsupportedFormat
        }

        let localFileNameLength = Int(data.readUInt16(at: localHeaderOffset + 26))
        let localExtraFieldLength = Int(data.readUInt16(at: localHeaderOffset + 28))
        let payloadOffset = localHeaderOffset + 30 + localFileNameLength + localExtraFieldLength
        let payloadEnd = payloadOffset + entry.compressedSize

        guard payloadOffset >= 0, payloadEnd >= payloadOffset, payloadEnd <= data.count else {
            throw EPubParseError.unsupportedFormat
        }

        return data.subdata(in: payloadOffset..<payloadEnd)
    }

    private static func decompressZIPPayload(
        _ payload: Data,
        method: UInt16,
        expectedSize: Int,
        generalPurposeFlag: UInt16
    ) throws -> Data {
        // bit 0 = encrypted
        if (generalPurposeFlag & 0x0001) != 0 {
            throw EPubParseError.unsupportedFormat
        }

        switch method {
        case 0:
            return payload
        case 8:
            if let inflated = try? inflateRawDeflateData(payload, expectedSize: expectedSize) {
                return inflated
            }
            if let zlibWrapped = try? inflateZlibWrappedData(payload, expectedSize: expectedSize) {
                return zlibWrapped
            }
            throw EPubParseError.unsupportedFormat
        default:
            throw EPubParseError.unsupportedFormat
        }
    }

    private static func inflateRawDeflateData(_ data: Data, expectedSize: Int) throws -> Data {
        try inflateData(data, windowBits: -MAX_WBITS, expectedSize: expectedSize)
    }

    private static func inflateZlibWrappedData(_ data: Data, expectedSize: Int) throws -> Data {
        try inflateData(data, windowBits: MAX_WBITS, expectedSize: expectedSize)
    }

    private static func inflateData(_ data: Data, windowBits: Int32, expectedSize: Int) throws -> Data {
        if data.isEmpty {
            return Data()
        }

        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            windowBits,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw EPubParseError.unsupportedFormat
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        output.reserveCapacity(max(expectedSize, 0))
        let chunkSize = max(16_384, min(max(expectedSize, 0), 262_144))

        let finalStatus: Int32 = data.withUnsafeBytes { rawInput in
            guard let inputBase = rawInput.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer(mutating: inputBase)
            stream.avail_in = uInt(rawInput.count)

            while true {
                var chunk = [UInt8](repeating: 0, count: chunkSize)
                let status = chunk.withUnsafeMutableBytes { rawOutput -> Int32 in
                    guard let outputBase = rawOutput.bindMemory(to: Bytef.self).baseAddress else {
                        return Z_DATA_ERROR
                    }
                    stream.next_out = outputBase
                    stream.avail_out = uInt(rawOutput.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                let produced = chunk.count - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }

                if status == Z_STREAM_END {
                    return status
                }
                if status != Z_OK {
                    return status
                }
                if stream.avail_in == 0 && produced == 0 {
                    return Z_DATA_ERROR
                }
            }
        }

        guard finalStatus == Z_STREAM_END else {
            throw EPubParseError.unsupportedFormat
        }
        return output
    }
    
    // MARK: - XML解析辅助方法
    
    private static func parseContainerXML(_ data: Data) -> String? {
        if let rootFilePath = parseContainerWithXMLParser(data) {
            return rootFilePath
        }

        guard let xmlString = decodeXMLText(data) else { return nil }

        // 回退：兼容单双引号
        if let range = xmlString.range(of: "full-path\\s*=\\s*['\"]([^'\"]+)['\"]", options: .regularExpression) {
            let match = String(xmlString[range])
            if let pathRange = match.range(of: "['\"]([^'\"]+)['\"]", options: .regularExpression) {
                var path = String(match[pathRange])
                path = path.replacingOccurrences(of: "\"", with: "")
                path = path.replacingOccurrences(of: "'", with: "")
                return path
            }
        }

        return nil
    }
    
    private static func parseOPFFile(_ data: Data) -> OPFInfo {
        if let parsed = parseOPFWithXMLParser(data), !parsed.manifestMap.isEmpty {
            DebugLogger.info(
                "EPubParser: 解析OPF完成(XML) - manifest项: \(parsed.manifestMap.count), spine项: \(parsed.spineItems.count), TOC ID: \(parsed.tocId ?? "无"), NAV ID: \(parsed.navId ?? "无")"
            )
            return parsed
        }

        let fallback = parseOPFWithRegex(data)
        DebugLogger.info(
            "EPubParser: 解析OPF完成(Regex回退) - manifest项: \(fallback.manifestMap.count), spine项: \(fallback.spineItems.count), TOC ID: \(fallback.tocId ?? "无"), NAV ID: \(fallback.navId ?? "无")"
        )
        return fallback
    }

    private static func parseContainerWithXMLParser(_ data: Data) -> String? {
        final class ContainerDelegate: NSObject, XMLParserDelegate {
            var rootFilePath: String?

            func parser(
                _ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]
            ) {
                guard rootFilePath == nil else { return }
                let name = elementName.lowercased()
                guard name == "rootfile" || name.hasSuffix(":rootfile") else { return }
                if let fullPath = EPubParser.firstAttributeValue(named: "full-path", in: attributeDict), !fullPath.isEmpty {
                    rootFilePath = fullPath
                    parser.abortParsing()
                }
            }
        }

        let delegate = ContainerDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        return delegate.rootFilePath
    }

    private static func parseOPFWithXMLParser(_ data: Data) -> OPFInfo? {
        final class OPFDelegate: NSObject, XMLParserDelegate {
            var info = OPFInfo()
            private var currentText = ""
            private var currentMetaProperty: String?
            private var currentMetaRefines: String?

            func parser(
                _ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]
            ) {
                let name = elementName.lowercased()
                currentText = ""

                switch name {
                case _ where name == "spine" || name.hasSuffix(":spine"):
                    if let toc = EPubParser.firstAttributeValue(named: "toc", in: attributeDict), !toc.isEmpty {
                        info.tocId = toc
                    }
                case _ where name == "itemref" || name.hasSuffix(":itemref"):
                    guard let idref = EPubParser.firstAttributeValue(named: "idref", in: attributeDict), !idref.isEmpty else {
                        return
                    }
                    if let linear = EPubParser.firstAttributeValue(named: "linear", in: attributeDict),
                       linear.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no" {
                        DebugLogger.info("EPubParser: 跳过non-linear的spine项: \(idref)")
                        return
                    }
                    info.spineItems.append(idref)
                case _ where name == "item" || name.hasSuffix(":item"):
                    guard let id = EPubParser.firstAttributeValue(named: "id", in: attributeDict), !id.isEmpty,
                          let href = EPubParser.firstAttributeValue(named: "href", in: attributeDict), !href.isEmpty else {
                        return
                    }

                    let mediaType = EPubParser.firstAttributeValue(named: "media-type", in: attributeDict)?.lowercased()
                    let properties = EPubParser.tokenizedProperties(
                        EPubParser.firstAttributeValue(named: "properties", in: attributeDict)
                    )
                    info.manifestMap[id] = href
                    info.manifestItems[id] = OPFInfo.ManifestItem(
                        id: id,
                        href: href,
                        mediaType: mediaType,
                        properties: properties
                    )

                    if properties.contains("nav"), info.navId == nil {
                        info.navId = id
                    }
                    if properties.contains("nav") {
                        info.tocCandidateIds.append(id)
                    }
                    if mediaType == "application/x-dtbncx+xml" || href.lowercased().hasSuffix(".ncx") {
                        info.tocCandidateIds.append(id)
                    }
                    if properties.contains("cover-image") {
                        if info.coverId == nil {
                            info.coverId = id
                        }
                        if info.coverHref == nil {
                            info.coverHref = href
                        }
                    }
                case _ where name == "meta" || name.hasSuffix(":meta"):
                    if let coverName = EPubParser.firstAttributeValue(named: "name", in: attributeDict)?.lowercased(),
                       coverName == "cover",
                       let content = EPubParser.firstAttributeValue(named: "content", in: attributeDict),
                       !content.isEmpty {
                        info.coverId = EPubParser.normalizeManifestIdentifier(content)
                    }

                    if let property = EPubParser.firstAttributeValue(named: "property", in: attributeDict)?.lowercased() {
                        currentMetaProperty = property
                        currentMetaRefines = EPubParser.firstAttributeValue(named: "refines", in: attributeDict)

                        if property == "cover-image",
                           let content = EPubParser.firstAttributeValue(named: "content", in: attributeDict),
                           !content.isEmpty {
                            info.coverId = EPubParser.normalizeManifestIdentifier(content)
                        }
                    } else {
                        currentMetaProperty = nil
                        currentMetaRefines = nil
                    }
                default:
                    break
                }
            }

            func parser(_ parser: XMLParser, foundCharacters string: String) {
                currentText += string
            }

            func parser(
                _ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?
            ) {
                let name = elementName.lowercased()
                let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

                switch name {
                case "dc:title", "title":
                    if info.title == nil, !trimmedText.isEmpty {
                        info.title = trimmedText
                    }
                case "dc:creator", "creator":
                    if info.author == nil, !trimmedText.isEmpty {
                        info.author = trimmedText
                    }
                case "dc:language", "language":
                    if info.language == nil, !trimmedText.isEmpty {
                        info.language = trimmedText
                    }
                case _ where name == "meta" || name.hasSuffix(":meta"):
                    if currentMetaProperty == "cover-image" {
                        if info.coverId == nil, let normalized = EPubParser.normalizeManifestIdentifier(trimmedText) {
                            info.coverId = normalized
                        }
                        if info.coverId == nil, let currentMetaRefines {
                            if let normalized = EPubParser.normalizeManifestIdentifier(currentMetaRefines) {
                                info.coverId = normalized
                            }
                        }
                    }
                    currentMetaProperty = nil
                    currentMetaRefines = nil
                default:
                    break
                }

                currentText = ""
            }
        }

        let delegate = OPFDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            DebugLogger.warning("EPubParser: XML解析OPF失败: \(parser.parserError?.localizedDescription ?? "未知错误")")
            return nil
        }

        delegate.info.tocCandidateIds = deduplicatedIDSequence(delegate.info.tocCandidateIds)
        if delegate.info.coverHref == nil,
           let coverId = delegate.info.coverId,
           let href = delegate.info.manifestMap[coverId] {
            delegate.info.coverHref = href
        }
        return delegate.info
    }

    private static func parseOPFWithRegex(_ data: Data) -> OPFInfo {
        var info = OPFInfo()
        guard let xmlString = decodeXMLText(data) else {
            return info
        }

        info.title = extractXMLTag(xmlString, tag: "dc:title")
        info.author = extractXMLTag(xmlString, tag: "dc:creator")
        info.language = extractXMLTag(xmlString, tag: "dc:language")

        if let coverMeta = xmlString.range(of: "<meta\\s+name=['\"]cover['\"]\\s+content=['\"]([^'\"]+)['\"]", options: .regularExpression) {
            let match = String(xmlString[coverMeta])
            if let contentRange = match.range(of: "content=['\"]([^'\"]+)['\"]", options: .regularExpression) {
                var coverId = String(match[contentRange])
                coverId = coverId.replacingOccurrences(of: "content=\"", with: "")
                coverId = coverId.replacingOccurrences(of: "content='", with: "")
                coverId = coverId.replacingOccurrences(of: "\"", with: "")
                coverId = coverId.replacingOccurrences(of: "'", with: "")
                info.coverId = normalizeManifestIdentifier(coverId)
            }
        }

        let manifestPattern = "<item\\s+([^>]+)>"
        if let manifestRange = xmlString.range(of: "<manifest>([\\s\\S]*?)</manifest>", options: .regularExpression) {
            let manifestContent = String(xmlString[manifestRange])
            let regex = try? NSRegularExpression(pattern: manifestPattern, options: [])
            let nsString = manifestContent as NSString
            let results = regex?.matches(
                in: manifestContent,
                options: [],
                range: NSRange(location: 0, length: nsString.length)
            )

            results?.forEach { result in
                let itemString = nsString.substring(with: result.range)
                guard let id = extractAttribute(from: itemString, attribute: "id"),
                      let href = extractAttribute(from: itemString, attribute: "href") else {
                    return
                }

                let mediaType = extractAttribute(from: itemString, attribute: "media-type")?.lowercased()
                let properties = tokenizedProperties(extractAttribute(from: itemString, attribute: "properties"))
                info.manifestMap[id] = href
                info.manifestItems[id] = OPFInfo.ManifestItem(
                    id: id,
                    href: href,
                    mediaType: mediaType,
                    properties: properties
                )

                if properties.contains("nav"), info.navId == nil {
                    info.navId = id
                }
                if properties.contains("nav") {
                    info.tocCandidateIds.append(id)
                }
                if mediaType == "application/x-dtbncx+xml" || href.lowercased().hasSuffix(".ncx") {
                    info.tocCandidateIds.append(id)
                }
                if properties.contains("cover-image") {
                    if info.coverId == nil {
                        info.coverId = id
                    }
                    if info.coverHref == nil {
                        info.coverHref = href
                    }
                }
            }
        }

        let spinePattern = "<itemref\\s+([^>]+)>"
        if let spineRange = xmlString.range(of: "<spine([\\s\\S]*?)</spine>", options: .regularExpression) {
            let spineContent = String(xmlString[spineRange])

            if let spineTagRange = xmlString.range(of: "<spine[^>]*>", options: .regularExpression) {
                let spineTag = String(xmlString[spineTagRange])
                info.tocId = extractAttribute(from: spineTag, attribute: "toc")
            }

            let regex = try? NSRegularExpression(pattern: spinePattern, options: [])
            let nsString = spineContent as NSString
            let results = regex?.matches(
                in: spineContent,
                options: [],
                range: NSRange(location: 0, length: nsString.length)
            )

            results?.forEach { result in
                let itemString = nsString.substring(with: result.range)
                if let idref = extractAttribute(from: itemString, attribute: "idref") {
                    if let linear = extractAttribute(from: itemString, attribute: "linear"), linear.lowercased() == "no" {
                        DebugLogger.info("EPubParser: 跳过non-linear的spine项: \(idref)")
                        return
                    }
                    info.spineItems.append(idref)
                }
            }
        }

        if info.coverHref == nil,
           let coverId = info.coverId,
           let coverHref = info.manifestMap[coverId] {
            info.coverHref = coverHref
        }
        info.tocCandidateIds = deduplicatedIDSequence(info.tocCandidateIds)
        return info
    }
    
    private static func extractXMLTag(_ xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]+)</\(tag)>"
        if let range = xml.range(of: pattern, options: .regularExpression) {
            var content = String(xml[range])
            content = content.replacingOccurrences(of: "<\(tag)>", with: "")
            content = content.replacingOccurrences(of: "</\(tag)>", with: "")
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private static func extractAttribute(from xml: String, attribute: String) -> String? {
        let pattern = "\(attribute)\\s*=\\s*['\"]([^'\"]+)['\"]"
        if let range = xml.range(of: pattern, options: .regularExpression) {
            var value = String(xml[range])
            value = value.replacingOccurrences(of: "\(attribute)=\"", with: "")
            value = value.replacingOccurrences(of: "\(attribute)='", with: "")
            value = value.replacingOccurrences(of: "\"", with: "")
            value = value.replacingOccurrences(of: "'", with: "")
            return value
        }
        return nil
    }

    private static func decodeXMLText(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1,
            .windowsCP1252
        ]

        for encoding in encodings {
            if let value = String(data: data, encoding: encoding) {
                return value
            }
        }
        return nil
    }

    private static func firstAttributeValue(named attributeName: String, in attributes: [String: String]) -> String? {
        if let exact = attributes[attributeName] {
            return exact
        }

        let lowercasedName = attributeName.lowercased()
        for (key, value) in attributes {
            let normalizedKey = key.lowercased()
            if normalizedKey == lowercasedName || normalizedKey.hasSuffix(":\(lowercasedName)") {
                return value
            }
        }
        return nil
    }

    private static func tokenizedProperties(_ propertiesValue: String?) -> Set<String> {
        guard let propertiesValue else { return [] }
        let tokens = propertiesValue
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.lowercased() }
        return Set(tokens)
    }

    private static func normalizeManifestIdentifier(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var normalized = trimmed
        while normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        return normalized.isEmpty ? nil : normalized
    }

    private static func deduplicatedIDSequence(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for id in ids where !id.isEmpty {
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }

    private static func resolveRelativePathURL(_ href: String, relativeTo baseURL: URL) -> URL {
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

    // MARK: - 非内容项过滤
    
    private static func isCoverLikeTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let keywords = ["cover", "cover page", "front cover", "封面"]
        return keywords.contains(normalized) || normalized.hasPrefix("cover ")
    }
    
    private static func isCoverLikeHref(_ href: String) -> Bool {
        let fileName = (href as NSString).lastPathComponent.lowercased()
        let baseName = (fileName as NSString).deletingPathExtension
        
        if baseName == "cover"
            || baseName == "coverpage"
            || baseName == "cover-page"
            || baseName.hasPrefix("coverpage")
            || baseName == "frontcover"
            || baseName.hasPrefix("frontcover") {
            return true
        }
        
        if baseName.hasPrefix("cover") {
            let suffix = baseName.dropFirst("cover".count)
            if suffix.isEmpty {
                return true
            }
            if let first = suffix.first, first == "-" || first == "_" || first.isWholeNumber {
                return true
            }
        }
        
        return false
    }
    
    private static func shouldIgnoreTOCEntry(title: String, href: String) -> Bool {
        return isCoverLikeTitle(title) || isCoverLikeHref(href)
    }

    private static func decodeTOCHref(_ href: String) -> String {
        href.removingPercentEncoding ?? href
    }

    private static func normalizeTOCHrefPath(_ href: String) -> String {
        decodeTOCHref(href).components(separatedBy: "#").first ?? decodeTOCHref(href)
    }
    
    private static func shouldSkipChapter(title: String?, href: String, idref: String, coverId: String?) -> Bool {
        if let title = title, isCoverLikeTitle(title) {
            return true
        }
        if isCoverLikeHref(href) {
            return true
        }
        let lowerIdref = idref.lowercased()
        if lowerIdref == "cover" || lowerIdref.hasPrefix("cover-") || lowerIdref.hasPrefix("cover_") {
            return true
        }
        if let coverId = coverId?.lowercased(), coverId == lowerIdref {
            return true
        }
        return false
    }

    private static func mapTOCEntriesToChapters(_ tocEntries: [TOCEntry], hrefToChapterIndex: [String: Int]) -> [TOCItem] {
        var items: [TOCItem] = []
        
        for entry in tocEntries {
            let decodedHref = decodeTOCHref(entry.href)
            let normalizedHref = normalizeTOCHrefPath(decodedHref)
            let fileName = (decodedHref as NSString).lastPathComponent
            let normalizedFileName = (normalizedHref as NSString).lastPathComponent
            
            var matchedIndex: Int?
            
            for candidate in [normalizedHref, normalizedFileName, decodedHref, fileName] {
                if let idx = hrefToChapterIndex[candidate] {
                    matchedIndex = idx
                    break
                }
            }
            
            if matchedIndex == nil {
                for (href, idx) in hrefToChapterIndex {
                    if href.hasSuffix(normalizedFileName) || href.hasSuffix(fileName) {
                        matchedIndex = idx
                        break
                    }
                }
            }
            
            guard let chapterIndex = matchedIndex else {
                DebugLogger.warning("EPubParser: TOC条目未匹配章节 - \(entry.title) -> \(decodedHref)")
                continue
            }
            
            items.append(
                TOCItem(
                    title: entry.title,
                    href: decodedHref,
                    level: max(entry.level, 0),
                    chapterIndex: chapterIndex
                )
            )
        }
        
        return items
    }
    
    // MARK: - 目录解析
    
    private static func parseTOC(opfInfo: OPFInfo, baseURL: URL, coverId: String?) -> [TOCEntry] {
        let candidates = buildTOCCandidateIds(from: opfInfo)
        if candidates.isEmpty {
            DebugLogger.info("EPubParser: 未找到TOC候选项")
            return []
        }

        for candidateId in candidates {
            guard let tocHref = opfInfo.manifestMap[candidateId] else { continue }
            let tocURL = resolveRelativePathURL(tocHref, relativeTo: baseURL)
            guard let tocData = try? Data(contentsOf: tocURL),
                  let tocString = decodeXMLText(tocData) else {
                DebugLogger.warning("EPubParser: 无法读取TOC文件: id=\(candidateId), href=\(tocHref)")
                continue
            }

            let mediaType = opfInfo.manifestItems[candidateId]?.mediaType
            let tocEntries = parseTOCEntries(
                tocString: tocString,
                mediaType: mediaType,
                coverId: coverId
            )

            if !tocEntries.isEmpty {
                DebugLogger.info("EPubParser: TOC解析成功 - id=\(candidateId), href=\(tocHref), 条目=\(tocEntries.count)")
                return tocEntries
            }
        }

        DebugLogger.info("EPubParser: TOC候选项全部解析失败")
        return []
    }

    private static func parseTOCEntries(tocString: String, mediaType: String?, coverId: String?) -> [TOCEntry] {
        let normalizedMediaType = mediaType?.lowercased()

        if normalizedMediaType == "application/x-dtbncx+xml" || tocString.contains("<ncx") {
            return parseNCX(tocString, coverId: coverId)
        }
        if normalizedMediaType == "application/xhtml+xml"
            || normalizedMediaType == "text/html"
            || tocString.contains("epub:type=\"toc\"")
            || tocString.contains("<nav") {
            return parseNAV(tocString, coverId: coverId)
        }
        return []
    }

    private static func buildTOCCandidateIds(from info: OPFInfo) -> [String] {
        var orderedIds: [String] = []
        func append(_ id: String?) {
            guard let id, !id.isEmpty, !orderedIds.contains(id) else { return }
            orderedIds.append(id)
        }

        // 优先保持 EPUB2 的 spine toc 逻辑，再补 EPUB3 nav 候选
        append(info.tocId)
        append(info.navId)
        info.tocCandidateIds.forEach { append($0) }

        for key in info.manifestItems.keys.sorted() {
            guard let item = info.manifestItems[key] else { continue }
            let hrefLower = item.href.lowercased()
            if item.properties.contains("nav")
                || item.mediaType == "application/x-dtbncx+xml"
                || hrefLower.hasSuffix(".ncx")
                || hrefLower.hasSuffix("nav.xhtml")
                || hrefLower.contains("toc") {
                append(item.id)
            }
        }

        return orderedIds
    }
    
    private static func parseNCX(_ ncxString: String, coverId: String?) -> [TOCEntry] {
        if let data = ncxString.data(using: .utf8),
           let parsed = parseNCXWithXMLParser(data: data, coverId: coverId),
           !parsed.isEmpty {
            return parsed
        }
        return parseNCXWithRegex(ncxString)
    }
    
    private static func parseNCXWithRegex(_ ncxString: String) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        
        let navPointPattern = "<navPoint[^>]*>([\\s\\S]*?)</navPoint>"
        guard let regex = try? NSRegularExpression(pattern: navPointPattern, options: []) else {
            return []
        }
        
        let nsString = ncxString as NSString
        let matches = regex.matches(in: ncxString, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let navPointContent = nsString.substring(with: match.range)
            
            if let textRange = navPointContent.range(of: "<text>([^<]+)</text>", options: .regularExpression) {
                var title = String(navPointContent[textRange])
                title = title.replacingOccurrences(of: "<text>", with: "")
                title = title.replacingOccurrences(of: "</text>", with: "")
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let contentRange = navPointContent.range(of: "<content\\s+src=\"([^\"]+)\"", options: .regularExpression) {
                    let contentTag = String(navPointContent[contentRange])
                    if let href = extractAttribute(from: contentTag, attribute: "src") {
                        let decodedHref = decodeTOCHref(href)
                        let normalizedHref = normalizeTOCHrefPath(decodedHref)
                        
                        if shouldIgnoreTOCEntry(title: title, href: normalizedHref) {
                            DebugLogger.info("EPubParser: 跳过封面类NCX条目 - \(title) -> \(normalizedHref)")
                            continue
                        }
                        
                        let order = entries.count
                        entries.append(TOCEntry(title: title, href: decodedHref, order: order, level: 0))
                        let position = order + 1
                        maybeLogTOCEntry(
                            "EPubParser: NCX条目[\(position)] - \(title) -> \(decodedHref)",
                            position: position
                        )
                    }
                }
            }
        }
        
        return entries
    }
    
    private static func parseNAV(_ navString: String, coverId: String?) -> [TOCEntry] {
        if let data = navString.data(using: .utf8),
           let parsed = parseNAVWithXMLParser(data: data, coverId: coverId, requireExplicitTOCNav: true),
           !parsed.isEmpty {
            return parsed
        }
        if let data = navString.data(using: .utf8),
           let parsed = parseNAVWithXMLParser(data: data, coverId: coverId, requireExplicitTOCNav: false),
           !parsed.isEmpty {
            return parsed
        }
        return parseNAVWithRegex(navString)
    }
    
    private static func parseNAVWithRegex(_ navString: String) -> [TOCEntry] {
        var entries: [TOCEntry] = []

        let navRange =
            navString.range(
                of: "<nav[^>]*(epub:type|type|role)=\"[^\"]*(toc|doc-toc)[^\"]*\"[^>]*>([\\s\\S]*?)</nav>",
                options: [.regularExpression, .caseInsensitive]
            )
            ?? navString.range(of: "<nav[^>]*>([\\s\\S]*?)</nav>", options: .regularExpression)

        guard let navRange else {
            DebugLogger.warning("EPubParser: 未找到可解析的nav标签")
            return []
        }

        let navContent = String(navString[navRange])
        
        let linkPattern = "<a[^>]+href=\"([^\"]+)\"[^>]*>([^<]+)</a>"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
            return []
        }
        
        let nsString = navContent as NSString
        let matches = regex.matches(in: navContent, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let linkContent = nsString.substring(with: match.range)
            
            if let href = extractAttribute(from: linkContent, attribute: "href") {
                if let textRange = linkContent.range(of: ">([^<]+)<", options: .regularExpression) {
                    var title = String(linkContent[textRange])
                    title = title.replacingOccurrences(of: ">", with: "")
                    title = title.replacingOccurrences(of: "<", with: "")
                    title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let decodedHref = EPubParser.decodeTOCHref(href)
                    let normalizedHref = EPubParser.normalizeTOCHrefPath(decodedHref)
                    
                    if shouldIgnoreTOCEntry(title: title, href: normalizedHref) {
                        DebugLogger.info("EPubParser: 跳过封面类NAV条目 - \(title) -> \(normalizedHref)")
                        continue
                    }
                    
                    let order = entries.count
                    entries.append(TOCEntry(title: title, href: decodedHref, order: order, level: 0))
                    let position = order + 1
                    maybeLogTOCEntry(
                        "EPubParser: NAV条目[\(position)] - \(title) -> \(decodedHref)",
                        position: position
                    )
                }
            }
        }
        
        return entries
    }

    private static func parseNCXWithXMLParser(data: Data, coverId _: String?) -> [TOCEntry]? {
        final class NCXParserDelegate: NSObject, XMLParserDelegate {
            struct NavPointContext {
                var level: Int
                var startIndex: Int
                var title: String?
                var href: String?
            }
            
            var entries: [TOCEntry] = []
            private var stack: [NavPointContext] = []
            private var currentText: String = ""
            
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
                let name = elementName.lowercased()
                
                if name.hasSuffix("navpoint") {
                    let level = (stack.last?.level ?? -1) + 1
                    let context = NavPointContext(level: level, startIndex: entries.count, title: nil, href: nil)
                    stack.append(context)
                    currentText = ""
                } else if name == "text" {
                    currentText = ""
                } else if name.hasSuffix("content") {
                    if let src = attributeDict["src"] ?? attributeDict["href"] {
                        if var last = stack.popLast() {
                            last.href = src
                            stack.append(last)
                        }
                    }
                }
            }
            
            func parser(_ parser: XMLParser, foundCharacters string: String) {
                currentText += string
            }
            
            func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
                let name = elementName.lowercased()
                
                if name == "text" {
                    let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, var last = stack.popLast() {
                        last.title = trimmed
                        stack.append(last)
                    }
                    currentText = ""
                } else if name.hasSuffix("navpoint") {
                    guard let context = stack.popLast() else { return }
                    
                    guard let rawTitle = context.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !rawTitle.isEmpty,
                          let href = context.href else {
                        currentText = ""
                        return
                    }
                    
                    let decodedHref = EPubParser.decodeTOCHref(href)
                    let normalizedHref = EPubParser.normalizeTOCHrefPath(decodedHref)
                    
                    if EPubParser.shouldIgnoreTOCEntry(title: rawTitle, href: normalizedHref) {
                        DebugLogger.info("EPubParser: 跳过封面类NCX条目(XML) - \(rawTitle) -> \(normalizedHref)")
                    } else {
                        let entry = TOCEntry(title: rawTitle, href: decodedHref, order: context.startIndex, level: context.level)
                        entries.insert(entry, at: context.startIndex)
                        EPubParser.maybeLogTOCEntry(
                            "EPubParser: NCX条目(XML)插入[\(context.startIndex + 1)] - \(rawTitle) -> \(decodedHref), level=\(context.level)",
                            position: entries.count
                        )
                    }
                    
                    currentText = ""
                }
            }
        }
        
        let delegate = NCXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        
        let success = parser.parse()
        if !success {
            DebugLogger.warning("EPubParser: XML解析NCX失败: \(parser.parserError?.localizedDescription ?? "未知错误")")
        }
        
        let normalizedEntries = delegate.entries.enumerated().map { index, entry in
            TOCEntry(title: entry.title, href: entry.href, order: index, level: entry.level)
        }
        
        return normalizedEntries
    }
    
    private static func parseNAVWithXMLParser(data: Data, coverId _: String?, requireExplicitTOCNav: Bool) -> [TOCEntry]? {
        final class NAVParserDelegate: NSObject, XMLParserDelegate {
            var entries: [TOCEntry] = []
            private var insideTOCNav = false
            private var navDepth = 0
            private var listDepth = 0
            private var currentHref: String?
            private var currentText: String = ""
            private var capturingLinkText = false
            private let requireExplicitTOCNav: Bool
            private var hasMatchedExplicitTOCNav = false

            init(requireExplicitTOCNav: Bool) {
                self.requireExplicitTOCNav = requireExplicitTOCNav
            }
            
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
                let name = elementName.lowercased()
                
                if name == "nav" {
                    navDepth += 1
                    let navigationRole = (
                        attributeDict["epub:type"]
                        ?? attributeDict["type"]
                        ?? attributeDict["role"]
                        ?? ""
                    ).lowercased()
                    let isExplicitTOCNav = navigationRole.contains("toc") || navigationRole.contains("doc-toc")

                    if isExplicitTOCNav {
                        insideTOCNav = true
                        hasMatchedExplicitTOCNav = true
                    } else if !requireExplicitTOCNav && !hasMatchedExplicitTOCNav && navDepth == 1 {
                        // 部分EPUB3未标注epub:type=toc，回退到首个nav
                        insideTOCNav = true
                    }
                }
                
                guard insideTOCNav else { return }
                
                if name == "ol" || name == "ul" {
                    listDepth += 1
                } else if name == "a" {
                    currentHref = attributeDict["href"]
                    currentText = ""
                    capturingLinkText = true
                }
            }
            
            func parser(_ parser: XMLParser, foundCharacters string: String) {
                guard capturingLinkText else { return }
                currentText += string
            }
            
            func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
                let name = elementName.lowercased()
                
                if !insideTOCNav {
                    if name == "nav" && navDepth > 0 {
                        navDepth -= 1
                    }
                    return
                }
                
                if name == "a" {
                    capturingLinkText = false
                    let title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let href = currentHref
                    currentText = ""
                    currentHref = nil
                    
                    guard !title.isEmpty, let href = href else { return }
                    
                    let decodedHref = EPubParser.decodeTOCHref(href)
                    let normalizedHref = EPubParser.normalizeTOCHrefPath(decodedHref)
                    if EPubParser.shouldIgnoreTOCEntry(title: title, href: normalizedHref) {
                        DebugLogger.info("EPubParser: 跳过封面类NAV条目(XML) - \(title) -> \(normalizedHref)")
                    } else {
                        let level = max(listDepth - 1, 0)
                        let order = entries.count
                        entries.append(TOCEntry(title: title, href: decodedHref, order: order, level: level))
                        EPubParser.maybeLogTOCEntry(
                            "EPubParser: NAV条目(XML)[\(order + 1)] - \(title) -> \(decodedHref), level=\(level)",
                            position: entries.count
                        )
                    }
                } else if name == "ol" || name == "ul" {
                    listDepth = max(listDepth - 1, 0)
                } else if name == "nav" {
                    navDepth = max(navDepth - 1, 0)
                    if navDepth == 0 {
                        insideTOCNav = false
                        listDepth = 0
                    }
                }
            }
        }
        
        let delegate = NAVParserDelegate(requireExplicitTOCNav: requireExplicitTOCNav)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        
        let success = parser.parse()
        if !success {
            DebugLogger.warning("EPubParser: XML解析NAV失败: \(parser.parserError?.localizedDescription ?? "未知错误")")
        }
        
        let normalizedEntries = delegate.entries.enumerated().map { index, entry in
            TOCEntry(title: entry.title, href: entry.href, order: index, level: entry.level)
        }
        
        return normalizedEntries
    }
    
    // MARK: - 章节解析
    
    private static func parseChapters(spineItems: [String], manifestMap: [String: String], baseURL: URL, tocEntries: [TOCEntry], coverId: String?) throws -> (chapters: [Chapter], hrefToChapterIndex: [String: Int]) {
        DebugLogger.info("EPubParser: 开始解析章节")
        DebugLogger.info("EPubParser: Spine中有 \(spineItems.count) 个项目")
        DebugLogger.info("EPubParser: Manifest中有 \(manifestMap.count) 个项目")
        DebugLogger.info("EPubParser: TOC中有 \(tocEntries.count) 个条目")
        
        // 创建 href -> title 的映射
        var hrefToTitle: [String: String] = [:]
        for entry in tocEntries {
            let normalizedHref = normalizeTOCHrefPath(entry.href)
            if hrefToTitle[normalizedHref] == nil {
                hrefToTitle[normalizedHref] = entry.title
            }
            let fileName = (normalizedHref as NSString).lastPathComponent
            if hrefToTitle[fileName] == nil {
                hrefToTitle[fileName] = entry.title
            }
        }
        
        var chapters: [Chapter] = []
        var hrefToChapterIndex: [String: Int] = [:]
        
        for idref in spineItems {
            guard let href = manifestMap[idref] else {
                DebugLogger.warning("EPubParser: 跳过无效的spine项目: \(idref)")
                continue
            }
            
            // 解码 URL 编码的路径
            guard let decodedHref = href.removingPercentEncoding else {
                DebugLogger.warning("EPubParser: 无法解码href: \(href)")
                continue
            }
            
            let normalizedHref = decodedHref.components(separatedBy: "#").first ?? decodedHref
            let fileName = (normalizedHref as NSString).lastPathComponent
            
            // 优先从 TOC 中找出标题，后续可根据 HTML 再做补充
            var chapterTitle: String?
            if let tocTitle = hrefToTitle[normalizedHref] {
                chapterTitle = tocTitle
            } else if let tocTitle = hrefToTitle[fileName] {
                chapterTitle = tocTitle
            } else {
                for (tocHref, tocTitle) in hrefToTitle {
                    if tocHref.hasSuffix(fileName) || tocHref.contains(fileName) {
                        chapterTitle = tocTitle
                        break
                    }
                }
            }
            
            if shouldSkipChapter(title: chapterTitle, href: normalizedHref, idref: idref, coverId: coverId) {
                DebugLogger.info("EPubParser: 跳过封面类章节 - \(chapterTitle ?? fileName)")
                continue
            }
            
            let chapterURL = resolveRelativePathURL(decodedHref, relativeTo: baseURL)
            
            do {
                let htmlContent = try String(contentsOf: chapterURL, encoding: .utf8)
                let chapterContent = cleanHTML(htmlContent)
                
                // 如果TOC中没有找到，尝试从HTML提取
                if chapterTitle == nil {
                    chapterTitle = extractChapterTitleFromHTML(htmlContent)
                }
                
                // 如果还是没有，使用默认标题
                let finalTitle = chapterTitle ?? "Chapter \(chapters.count + 1)"
                
                if shouldSkipChapter(title: finalTitle, href: normalizedHref, idref: idref, coverId: coverId) {
                    DebugLogger.info("EPubParser: 解析后跳过封面类章节 - \(finalTitle)")
                    continue
                }
                
                // 清理HTML用于移动端显示，并嵌入图片
                let cleanedHTML = cleanHTMLForMobileDisplay(htmlContent, baseURL: chapterURL.deletingLastPathComponent())
                
                let chapterIndex = chapters.count
                if hrefToChapterIndex[normalizedHref] == nil {
                    hrefToChapterIndex[normalizedHref] = chapterIndex
                }
                if hrefToChapterIndex[fileName] == nil {
                    hrefToChapterIndex[fileName] = chapterIndex
                }
                
                let chapter = Chapter(
                    title: finalTitle,
                    content: chapterContent,
                    htmlContent: cleanedHTML,
                    order: chapterIndex
                )
                
                chapters.append(chapter)
                DebugLogger.info("EPubParser: 解析章节[\(chapters.count)] - \(finalTitle) (内容长度: \(chapterContent.count) 字符)")
                
            } catch {
                DebugLogger.warning("EPubParser: 无法读取章节文件: \(chapterURL.path), 错误: \(error.localizedDescription)")
            }
        }
        
        return (chapters, hrefToChapterIndex)
    }
    
    private static func extractChapterTitleFromHTML(_ htmlString: String) -> String? {
        // 尝试从HTML标签中提取标题
        
        // 1. 尝试提取 <title> 标签
        if let titleRange = htmlString.range(of: "<title>([^<]+)</title>", options: .regularExpression) {
            var title = String(htmlString[titleRange])
            title = title.replacingOccurrences(of: "<title>", with: "")
            title = title.replacingOccurrences(of: "</title>", with: "")
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 移除常见的书名前缀/后缀（如 "Project Gutenberg"）
            let cleanedTitle = cleanTitleString(title)
            if !cleanedTitle.isEmpty && cleanedTitle.count < 200 {
                return cleanedTitle
            }
        }
        
        // 2. 尝试提取 <h1> 标签
        if let h1Range = htmlString.range(of: "<h1[^>]*>([\\s\\S]*?)</h1>", options: .regularExpression) {
            var title = String(htmlString[h1Range])
            title = title.replacingOccurrences(of: "<h1[^>]*>", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "</h1>", with: "")
            title = cleanHTML(title)
            
            let cleanedTitle = cleanTitleString(title)
            if !cleanedTitle.isEmpty && cleanedTitle.count < 200 {
                return cleanedTitle
            }
        }
        
        // 3. 尝试提取 <h2> 标签
        if let h2Range = htmlString.range(of: "<h2[^>]*>([\\s\\S]*?)</h2>", options: .regularExpression) {
            var title = String(htmlString[h2Range])
            title = title.replacingOccurrences(of: "<h2[^>]*>", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "</h2>", with: "")
            title = cleanHTML(title)
            
            let cleanedTitle = cleanTitleString(title)
            if !cleanedTitle.isEmpty && cleanedTitle.count < 200 {
                return cleanedTitle
            }
        }
        
        // 4. 尝试提取 <h3> 标签
        if let h3Range = htmlString.range(of: "<h3[^>]*>([\\s\\S]*?)</h3>", options: .regularExpression) {
            var title = String(htmlString[h3Range])
            title = title.replacingOccurrences(of: "<h3[^>]*>", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "</h3>", with: "")
            title = cleanHTML(title)
            
            let cleanedTitle = cleanTitleString(title)
            if !cleanedTitle.isEmpty && cleanedTitle.count < 200 {
                return cleanedTitle
            }
        }
        
        return nil
    }
    
    private static func cleanTitleString(_ title: String) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除常见的不需要的前缀/后缀
        let patternsToRemove = [
            "\\s*[|\\-–—]\\s*Project Gutenberg.*$",
            "^The Project Gutenberg.*?[|\\-–—]\\s*",
            "\\s*[|\\-–—]\\s*eBook.*$",
            "^eBook.*?[|\\-–—]\\s*"
        ]
        
        for pattern in patternsToRemove {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func cleanHTML(_ html: String) -> String {
        var text = html
        
        // 移除脚本和样式标签及其内容
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        
        // 移除所有HTML标签
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        
        // 解码HTML实体
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        
        // 清理多余的空白字符
        text = text.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n[ \t]+", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 清理HTML用于移动端显示，保留结构但移除不需要的元素
    private static func cleanHTMLForMobileDisplay(_ html: String, baseURL: URL) -> String {
        var cleanedHTML = html
        
        // 移除脚本和样式标签
        cleanedHTML = cleanedHTML.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        cleanedHTML = cleanedHTML.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        cleanedHTML = cleanedHTML.replacingOccurrences(of: "<link[^>]+rel=[\"']?stylesheet[\"']?[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        
        // 移除注释
        cleanedHTML = cleanedHTML.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        
        // 移除可能影响布局的内联样式中的固定宽度
        cleanedHTML = cleanedHTML.replacingOccurrences(of: "width:\\s*\\d+px", with: "width: 100%", options: .regularExpression)
        cleanedHTML = cleanedHTML.replacingOccurrences(of: "max-width:\\s*\\d+px", with: "max-width: 100%", options: .regularExpression)
        
        // 处理图片标签，将图片转换为base64嵌入
        cleanedHTML = embedImagesAsBase64(in: cleanedHTML, baseURL: baseURL)
        
        // 提取body内容（如果存在）
        if let bodyRange = cleanedHTML.range(of: "<body[^>]*>([\\s\\S]*?)</body>", options: .regularExpression) {
            let bodyContent = String(cleanedHTML[bodyRange])
            cleanedHTML = bodyContent.replacingOccurrences(of: "<body[^>]*>", with: "", options: .regularExpression)
            cleanedHTML = cleanedHTML.replacingOccurrences(of: "</body>", with: "")
        }

        // 删除会干扰阅读器页边距控制的横向布局内联样式
        cleanedHTML = sanitizeInlineStylesForReaderLayout(cleanedHTML)
        
        return cleanedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeInlineStylesForReaderLayout(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "style\\s*=\\s*(['\"])(.*?)\\1",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return html
        }

        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        let mutable = NSMutableString(string: html)

        for match in matches.reversed() {
            let originalStyle = nsString.substring(with: match.range(at: 2))
            let sanitizedStyle = sanitizeInlineStyleDeclaration(originalStyle)

            if sanitizedStyle.isEmpty {
                mutable.replaceCharacters(in: match.range, with: "")
            } else {
                mutable.replaceCharacters(in: match.range, with: "style=\"\(sanitizedStyle)\"")
            }
        }

        return String(mutable)
    }

    private static func sanitizeInlineStyleDeclaration(_ declaration: String) -> String {
        let blockedProperties: Set<String> = [
            "margin",
            "margin-left",
            "margin-right",
            "margin-inline",
            "margin-inline-start",
            "margin-inline-end",
            "padding",
            "padding-left",
            "padding-right",
            "padding-inline",
            "padding-inline-start",
            "padding-inline-end",
            "width",
            "min-width",
            "max-width",
            "left",
            "right",
            "inset",
            "inset-inline",
            "inset-inline-start",
            "inset-inline-end"
        ]

        let declarations = declaration.split(separator: ";", omittingEmptySubsequences: true)
        var kept: [String] = []

        for item in declarations {
            let pair = item.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }

            let propertyName = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if blockedProperties.contains(propertyName) {
                continue
            }

            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            kept.append("\(propertyName): \(value)")
        }

        return kept.joined(separator: "; ")
    }
    
    // 将HTML中的图片转换为base64嵌入
    private static func embedImagesAsBase64(in html: String, baseURL: URL) -> String {
        var result = html
        
        // 查找所有img标签
        let imgPattern = "<img[^>]+src=\"([^\"]+)\"[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: []) else {
            return result
        }
        
        let nsString = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // 从后往前替换，避免索引变化
        for match in matches.reversed() {
            let imgTag = nsString.substring(with: match.range)
            
            // 提取src属性
            if let srcRange = imgTag.range(of: "src=\"([^\"]+)\"", options: .regularExpression) {
                var src = String(imgTag[srcRange])
                src = src.replacingOccurrences(of: "src=\"", with: "")
                src = src.replacingOccurrences(of: "\"", with: "")
                
                // 跳过已经是base64或http的图片
                if src.hasPrefix("data:") || src.hasPrefix("http://") || src.hasPrefix("https://") {
                    continue
                }
                
                // 构建图片文件的完整路径
                let imageURL = resolveRelativePathURL(src, relativeTo: baseURL)
                
                // 尝试读取图片数据
                if let imageData = try? Data(contentsOf: imageURL) {
                    // 检测图片类型
                    let mimeType = getMimeType(from: src)
                    
                    // 转换为base64
                    let base64String = imageData.base64EncodedString()
                    let dataURI = "data:\(mimeType);base64,\(base64String)"
                    
                    // 替换原有的src
                    let newImgTag = imgTag.replacingOccurrences(of: src, with: dataURI)
                    result = result.replacingOccurrences(of: imgTag, with: newImgTag)
                    
                    DebugLogger.info("EPubParser: 嵌入图片 - \(src)")
                }
            }
        }
        
        return result
    }
    
    // 根据文件扩展名获取MIME类型
    private static func getMimeType(from filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "webp":
            return "image/webp"
        default:
            return "image/jpeg"
        }
    }
    
    // MARK: - 封面提取
    
    private static func extractCoverImage(coverId: String?, coverHref: String?, manifestMap: [String: String], baseURL: URL) -> Data? {
        // 如果有 cover id，尝试查找对应的图片
        if let coverId = coverId, let href = manifestMap[coverId] {
            let coverURL = resolveRelativePathURL(href, relativeTo: baseURL)
            return try? Data(contentsOf: coverURL)
        }

        if let coverHref {
            let coverURL = resolveRelativePathURL(coverHref, relativeTo: baseURL)
            return try? Data(contentsOf: coverURL)
        }
        
        // 如果没有找到，尝试查找第一个图片文件
        for (_, href) in manifestMap {
            if href.hasSuffix(".jpg") || href.hasSuffix(".jpeg") || 
               href.hasSuffix(".png") || href.hasSuffix(".gif") {
                let imageURL = resolveRelativePathURL(href, relativeTo: baseURL)
                if let imageData = try? Data(contentsOf: imageURL) {
                    return imageData
                }
            }
        }
        
        return nil
    }

    private static func makeFileFingerprint(for url: URL, fileManager: FileManager) -> ParsedFileFingerprint? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? (attributes[.size] as? Int64 ?? 0)
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return ParsedFileFingerprint(path: url.path, size: size, modifiedAt: modifiedAt)
    }

    private static func cachedMetadata(for fingerprint: ParsedFileFingerprint) -> EPubMetadata? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return metadataCache[fingerprint]?.metadata
    }

    private static func storeMetadataInCache(_ metadata: EPubMetadata, for fingerprint: ParsedFileFingerprint) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        metadataCache[fingerprint] = CachedMetadataEntry(metadata: metadata)
        metadataCacheOrder.removeAll { $0 == fingerprint }
        metadataCacheOrder.append(fingerprint)

        while metadataCacheOrder.count > metadataCacheLimit {
            let staleFingerprint = metadataCacheOrder.removeFirst()
            metadataCache.removeValue(forKey: staleFingerprint)
        }
    }

    private static func maybeLogTOCEntry(_ message: String, position: Int) {
        guard shouldLogTOCEntry(at: position) else { return }
        DebugLogger.info(message)
    }

    private static func shouldLogTOCEntry(at position: Int) -> Bool {
        guard position > 0 else { return false }
        if verboseTOCEntryLoggingEnabled {
            return true
        }
        if position <= tocEntryInitialDetailedCount {
            return true
        }
        return position % tocEntryProgressInterval == 0
    }

}



enum EPubParseError: Error {
    case invalidContainer
    case invalidOPF
    case fileNotFound
    case unsupportedFormat
    
    var localizedDescription: String {
        switch self {
        case .invalidContainer:
            return "无效的ePub容器文件"
        case .invalidOPF:
            return "无效的OPF文件"
        case .fileNotFound:
            return "文件未找到"
        case .unsupportedFormat:
            return "不支持的文件格式"
        }
    }
}

// MARK: - Data Extension for ZIP parsing

extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
