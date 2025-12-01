//
//  EPubParser.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/1/20.
//

import Foundation
import CoreData

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
}

struct OPFInfo {
    var title: String?
    var author: String?
    var language: String?
    var coverId: String?
    var manifestMap: [String: String] = [:]
    var spineItems: [String] = []
    var tocId: String? // NCX file ID
}

struct TOCEntry {
    let title: String
    let href: String
    let order: Int
    let level: Int
}

class EPubParser {
    
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
        
        // 获取文件属性
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            DebugLogger.info("EPubParser: 文件大小: \(fileSize) bytes")
        } catch {
            DebugLogger.warning("EPubParser: 无法获取文件属性: \(error.localizedDescription)")
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
            let tocEntries = parseTOC(tocId: opfInfo.tocId, manifestMap: opfInfo.manifestMap, baseURL: opfBaseURL, coverId: opfInfo.coverId)
            DebugLogger.info("EPubParser: 从TOC解析了 \(tocEntries.count) 个标题（含层级）")
            
            // 解析章节
            let chapterResult = try parseChapters(spineItems: opfInfo.spineItems, manifestMap: opfInfo.manifestMap, baseURL: opfBaseURL, tocEntries: tocEntries, coverId: opfInfo.coverId)
            let chapters = chapterResult.chapters
            DebugLogger.success("EPubParser: 成功解析 \(chapters.count) 个章节")
            
            // 将 TOC 映射到章节索引，保留层级
            let tocItems = mapTOCEntriesToChapters(tocEntries, hrefToChapterIndex: chapterResult.hrefToChapterIndex)
            
            // 提取封面图片（如果存在）
            let coverImageData = extractCoverImage(coverId: opfInfo.coverId, manifestMap: opfInfo.manifestMap, baseURL: opfBaseURL)
            
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
    
    private static func parseAndExtractZIP(data: Data, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        
        // ZIP 文件的魔术数字
        let zipMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04] // "PK\x03\x04"
        
        var offset = 0
        
        while offset < data.count - 30 {
            // 查找 Local File Header
            let header = data.subdata(in: offset..<min(offset + 4, data.count))
            
            if Array(header) != zipMagic {
                // 如果找不到更多文件头，说明到达中心目录区域
                break
            }
            
            // 读取 Local File Header (30 bytes + 文件名长度 + 额外字段长度)
            _ = data.readUInt16(at: offset + 4) // versionNeeded
            _ = data.readUInt16(at: offset + 6) // flags
            let compressionMethod = data.readUInt16(at: offset + 8)
            let compressedSize = Int(data.readUInt32(at: offset + 18))
            _ = data.readUInt32(at: offset + 22) // uncompressedSize
            let fileNameLength = Int(data.readUInt16(at: offset + 26))
            let extraFieldLength = Int(data.readUInt16(at: offset + 28))
            
            // 读取文件名
            let fileNameData = data.subdata(in: (offset + 30)..<(offset + 30 + fileNameLength))
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                offset += 30 + fileNameLength + extraFieldLength + compressedSize
                continue
            }
            
            // 跳过额外字段
            let dataOffset = offset + 30 + fileNameLength + extraFieldLength
            
            // 读取文件数据
            let fileData = data.subdata(in: dataOffset..<(dataOffset + compressedSize))
            
            // 创建文件路径
            let filePath = destinationURL.appendingPathComponent(fileName)
            
            // 如果是目录，创建目录
            if fileName.hasSuffix("/") {
                try fileManager.createDirectory(at: filePath, withIntermediateDirectories: true)
            } else {
                // 创建父目录
                let parentDir = filePath.deletingLastPathComponent()
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                
                // 解压文件数据
                let decompressedData: Data
                if compressionMethod == 0 {
                    // 无压缩
                    decompressedData = fileData
                } else if compressionMethod == 8 {
                    // Deflate 压缩
                    guard let decompressed = try? (fileData as NSData).decompressed(using: .zlib) as Data else {
                        offset += 30 + fileNameLength + extraFieldLength + compressedSize
                        continue
                    }
                    decompressedData = decompressed
                } else {
                    // 不支持的压缩方法
                    offset += 30 + fileNameLength + extraFieldLength + compressedSize
                    continue
                }
                
                // 写入文件
                try decompressedData.write(to: filePath)
            }
            
            // 移动到下一个条目
            offset += 30 + fileNameLength + extraFieldLength + compressedSize
        }
    }
    
    // MARK: - XML解析辅助方法
    
    private static func parseContainerXML(_ data: Data) -> String? {
        // 简单的正则表达式解析
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
        
        // 查找 <rootfile full-path="..." />
        if let range = xmlString.range(of: "full-path=\"([^\"]+)\"", options: .regularExpression) {
            let match = String(xmlString[range])
            if let pathRange = match.range(of: "\"([^\"]+)\"", options: .regularExpression) {
                var path = String(match[pathRange])
                path = path.replacingOccurrences(of: "\"", with: "")
                return path
            }
        }
        
        return nil
    }
    
    private static func parseOPFFile(_ data: Data) -> OPFInfo {
        var info = OPFInfo()
        
        guard let xmlString = String(data: data, encoding: .utf8) else {
            return info
        }
        
        // 解析 metadata
        info.title = extractXMLTag(xmlString, tag: "dc:title")
        info.author = extractXMLTag(xmlString, tag: "dc:creator")
        info.language = extractXMLTag(xmlString, tag: "dc:language")
        
        // 解析 cover id
        if let coverMeta = xmlString.range(of: "<meta\\s+name=\"cover\"\\s+content=\"([^\"]+)\"", options: .regularExpression) {
            let match = String(xmlString[coverMeta])
            if let contentRange = match.range(of: "content=\"([^\"]+)\"", options: .regularExpression) {
                var coverId = String(match[contentRange])
                coverId = coverId.replacingOccurrences(of: "content=\"", with: "")
                coverId = coverId.replacingOccurrences(of: "\"", with: "")
                info.coverId = coverId
            }
        }
        
        // 解析 manifest
        let manifestPattern = "<item\\s+([^>]+)>"
        if let manifestRange = xmlString.range(of: "<manifest>([\\s\\S]*?)</manifest>", options: .regularExpression) {
            let manifestContent = String(xmlString[manifestRange])
            
            let regex = try? NSRegularExpression(pattern: manifestPattern, options: [])
            let nsString = manifestContent as NSString
            let results = regex?.matches(in: manifestContent, options: [], range: NSRange(location: 0, length: nsString.length))
            
            results?.forEach { result in
                let itemString = nsString.substring(with: result.range)
                
                if let id = extractAttribute(from: itemString, attribute: "id"),
                   let href = extractAttribute(from: itemString, attribute: "href") {
                    info.manifestMap[id] = href
                }
            }
        }
        
        // 解析 spine (包括 toc 属性)
        let spinePattern = "<itemref\\s+([^>]+)>"
        if let spineRange = xmlString.range(of: "<spine([\\s\\S]*?)</spine>", options: .regularExpression) {
            let spineContent = String(xmlString[spineRange])
            
            // 提取 spine 标签的 toc 属性
            if let spineTagRange = xmlString.range(of: "<spine[^>]*>", options: .regularExpression) {
                let spineTag = String(xmlString[spineTagRange])
                info.tocId = extractAttribute(from: spineTag, attribute: "toc")
            }
            
            let regex = try? NSRegularExpression(pattern: spinePattern, options: [])
            let nsString = spineContent as NSString
            let results = regex?.matches(in: spineContent, options: [], range: NSRange(location: 0, length: nsString.length))
            
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
        
        DebugLogger.info("EPubParser: 解析OPF完成 - manifest项: \(info.manifestMap.count), spine项: \(info.spineItems.count), TOC ID: \(info.tocId ?? "无")")
        
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
        let pattern = "\(attribute)=\"([^\"]+)\""
        if let range = xml.range(of: pattern, options: .regularExpression) {
            var value = String(xml[range])
            value = value.replacingOccurrences(of: "\(attribute)=\"", with: "")
            value = value.replacingOccurrences(of: "\"", with: "")
            return value
        }
        return nil
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
            let normalizedHref = entry.href.components(separatedBy: "#").first ?? entry.href
            let decodedHref = normalizedHref.removingPercentEncoding ?? normalizedHref
            let fileName = (decodedHref as NSString).lastPathComponent
            
            var matchedIndex: Int?
            
            for candidate in [decodedHref, fileName] {
                if let idx = hrefToChapterIndex[candidate] {
                    matchedIndex = idx
                    break
                }
            }
            
            if matchedIndex == nil {
                for (href, idx) in hrefToChapterIndex {
                    if href.hasSuffix(fileName) {
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
    
    private static func parseTOC(tocId: String?, manifestMap: [String: String], baseURL: URL, coverId: String?) -> [TOCEntry] {
        guard let tocId = tocId, let tocHref = manifestMap[tocId] else {
            DebugLogger.info("EPubParser: 未找到TOC文件引用")
            return []
        }
        
        let tocURL = baseURL.appendingPathComponent(tocHref)
        guard let tocData = try? Data(contentsOf: tocURL),
              let tocString = String(data: tocData, encoding: .utf8) else {
            DebugLogger.warning("EPubParser: 无法读取TOC文件: \(tocHref)")
            return []
        }
        
        // 判断是NCX还是NAV格式
        if tocString.contains("<ncx") {
            return parseNCX(tocString, coverId: coverId)
        } else if tocString.contains("epub:type=\"toc\"") || tocString.contains("<nav") {
            return parseNAV(tocString, coverId: coverId)
        }
        
        return []
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
                        let normalizedHref = href.components(separatedBy: "#").first ?? href
                        let decodedHref = normalizedHref.removingPercentEncoding ?? normalizedHref
                        
                        if shouldIgnoreTOCEntry(title: title, href: decodedHref) {
                            DebugLogger.info("EPubParser: 跳过封面类NCX条目 - \(title) -> \(decodedHref)")
                            continue
                        }
                        
                        let order = entries.count
                        entries.append(TOCEntry(title: title, href: decodedHref, order: order, level: 0))
                        DebugLogger.info("EPubParser: NCX条目[\(order + 1)] - \(title) -> \(decodedHref)")
                    }
                }
            }
        }
        
        return entries
    }
    
    private static func parseNAV(_ navString: String, coverId: String?) -> [TOCEntry] {
        if let data = navString.data(using: .utf8),
           let parsed = parseNAVWithXMLParser(data: data, coverId: coverId),
           !parsed.isEmpty {
            return parsed
        }
        return parseNAVWithRegex(navString)
    }
    
    private static func parseNAVWithRegex(_ navString: String) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        
        guard let navRange = navString.range(of: "<nav[^>]*epub:type=\"toc\"[^>]*>([\\s\\S]*?)</nav>", options: .regularExpression) else {
            DebugLogger.warning("EPubParser: 未找到epub:type=\"toc\"的nav标签")
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
                    
                    let normalizedHref = href.components(separatedBy: "#").first ?? href
                    let decodedHref = normalizedHref.removingPercentEncoding ?? normalizedHref
                    
                    if shouldIgnoreTOCEntry(title: title, href: decodedHref) {
                        DebugLogger.info("EPubParser: 跳过封面类NAV条目 - \(title) -> \(decodedHref)")
                        continue
                    }
                    
                    let order = entries.count
                    entries.append(TOCEntry(title: title, href: decodedHref, order: order, level: 0))
                    DebugLogger.info("EPubParser: NAV条目[\(order + 1)] - \(title) -> \(decodedHref)")
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
                    
                    let normalizedHref = href.components(separatedBy: "#").first ?? href
                    let decodedHref = normalizedHref.removingPercentEncoding ?? normalizedHref
                    
                    if EPubParser.shouldIgnoreTOCEntry(title: rawTitle, href: decodedHref) {
                        DebugLogger.info("EPubParser: 跳过封面类NCX条目(XML) - \(rawTitle) -> \(decodedHref)")
                    } else {
                        let entry = TOCEntry(title: rawTitle, href: decodedHref, order: context.startIndex, level: context.level)
                        entries.insert(entry, at: context.startIndex)
                        DebugLogger.info("EPubParser: NCX条目(XML)插入[\(context.startIndex + 1)] - \(rawTitle) -> \(decodedHref), level=\(context.level)")
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
    
    private static func parseNAVWithXMLParser(data: Data, coverId _: String?) -> [TOCEntry]? {
        final class NAVParserDelegate: NSObject, XMLParserDelegate {
            var entries: [TOCEntry] = []
            private var insideTOCNav = false
            private var navDepth = 0
            private var listDepth = 0
            private var currentHref: String?
            private var currentText: String = ""
            private var capturingLinkText = false
            
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
                let name = elementName.lowercased()
                
                if name == "nav" {
                    navDepth += 1
                    if let epubType = attributeDict["epub:type"] ?? attributeDict["type"], epubType.contains("toc") {
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
                    
                    let normalizedHref = href.components(separatedBy: "#").first ?? href
                    let decodedHref = normalizedHref.removingPercentEncoding ?? normalizedHref
                    if EPubParser.shouldIgnoreTOCEntry(title: title, href: decodedHref) {
                        DebugLogger.info("EPubParser: 跳过封面类NAV条目(XML) - \(title) -> \(decodedHref)")
                    } else {
                        let level = max(listDepth - 1, 0)
                        let order = entries.count
                        entries.append(TOCEntry(title: title, href: decodedHref, order: order, level: level))
                        DebugLogger.info("EPubParser: NAV条目(XML)[\(order + 1)] - \(title) -> \(decodedHref), level=\(level)")
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
        
        let delegate = NAVParserDelegate()
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
            hrefToTitle[entry.href] = entry.title
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
            
            let chapterURL = baseURL.appendingPathComponent(decodedHref)
            
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
        
        return cleanedHTML.trimmingCharacters(in: .whitespacesAndNewlines)
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
                let imageURL = baseURL.appendingPathComponent(src)
                
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
    
    private static func extractCoverImage(coverId: String?, manifestMap: [String: String], baseURL: URL) -> Data? {
        // 如果有 cover id，尝试查找对应的图片
        if let coverId = coverId, let href = manifestMap[coverId] {
            let coverURL = baseURL.appendingPathComponent(href)
            return try? Data(contentsOf: coverURL)
        }
        
        // 如果没有找到，尝试查找第一个图片文件
        for (_, href) in manifestMap {
            if href.hasSuffix(".jpg") || href.hasSuffix(".jpeg") || 
               href.hasSuffix(".png") || href.hasSuffix(".gif") {
                let imageURL = baseURL.appendingPathComponent(href)
                if let imageData = try? Data(contentsOf: imageURL) {
                    return imageData
                }
            }
        }
        
        return nil
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
        return withUnsafeBytes { bytes in
            let pointer = bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt16.self)
            return UInt16(littleEndian: pointer.pointee)
        }
    }
    
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { bytes in
            let pointer = bytes.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
            return UInt32(littleEndian: pointer.pointee)
        }
    }
}
