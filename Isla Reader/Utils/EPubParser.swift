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
    let totalPages: Int
}

struct Chapter {
    let title: String
    let content: String
    let order: Int
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
            let tocEntries = parseTOC(tocId: opfInfo.tocId, manifestMap: opfInfo.manifestMap, baseURL: opfBaseURL)
            DebugLogger.info("EPubParser: 从TOC解析了 \(tocEntries.count) 个标题")
            
            // 解析章节
            let chapters = try parseChapters(spineItems: opfInfo.spineItems, manifestMap: opfInfo.manifestMap, baseURL: opfBaseURL, tocEntries: tocEntries)
            DebugLogger.success("EPubParser: 成功解析 \(chapters.count) 个章节")
            
            // 提取封面图片（如果存在）
            let coverImageData = extractCoverImage(coverId: opfInfo.coverId, manifestMap: opfInfo.manifestMap, baseURL: opfBaseURL)
            
            let metadata = EPubMetadata(
                title: title,
                author: author,
                language: language,
                coverImageData: coverImageData,
                chapters: chapters,
                totalPages: chapters.count * 10 // 粗略估计
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
    
    // MARK: - 目录解析
    
    private static func parseTOC(tocId: String?, manifestMap: [String: String], baseURL: URL) -> [TOCEntry] {
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
            return parseNCX(tocString, baseURL: tocURL.deletingLastPathComponent())
        } else if tocString.contains("epub:type=\"toc\"") || tocString.contains("<nav") {
            return parseNAV(tocString, baseURL: tocURL.deletingLastPathComponent())
        }
        
        return []
    }
    
    private static func parseNCX(_ ncxString: String, baseURL: URL) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        
        // 提取所有 navPoint 标签
        let navPointPattern = "<navPoint[^>]*>([\\s\\S]*?)</navPoint>"
        guard let regex = try? NSRegularExpression(pattern: navPointPattern, options: []) else {
            return []
        }
        
        let nsString = ncxString as NSString
        let matches = regex.matches(in: ncxString, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for (index, match) in matches.enumerated() {
            let navPointContent = nsString.substring(with: match.range)
            
            // 提取标题 (navLabel > text)
            if let textRange = navPointContent.range(of: "<text>([^<]+)</text>", options: .regularExpression) {
                var title = String(navPointContent[textRange])
                title = title.replacingOccurrences(of: "<text>", with: "")
                title = title.replacingOccurrences(of: "</text>", with: "")
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 提取 href (content src)
                if let contentRange = navPointContent.range(of: "<content\\s+src=\"([^\"]+)\"", options: .regularExpression) {
                    let contentTag = String(navPointContent[contentRange])
                    if let href = extractAttribute(from: contentTag, attribute: "src") {
                        // 规范化 href（移除锚点）
                        let normalizedHref = href.components(separatedBy: "#").first ?? href
                        
                        entries.append(TOCEntry(title: title, href: normalizedHref, order: index))
                        DebugLogger.info("EPubParser: NCX条目[\(index + 1)] - \(title) -> \(normalizedHref)")
                    }
                }
            }
        }
        
        return entries
    }
    
    private static func parseNAV(_ navString: String, baseURL: URL) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        
        // 提取 TOC nav 部分
        guard let navRange = navString.range(of: "<nav[^>]*epub:type=\"toc\"[^>]*>([\\s\\S]*?)</nav>", options: .regularExpression) else {
            DebugLogger.warning("EPubParser: 未找到epub:type=\"toc\"的nav标签")
            return []
        }
        
        let navContent = String(navString[navRange])
        
        // 提取所有链接
        let linkPattern = "<a[^>]+href=\"([^\"]+)\"[^>]*>([^<]+)</a>"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
            return []
        }
        
        let nsString = navContent as NSString
        let matches = regex.matches(in: navContent, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for (index, match) in matches.enumerated() {
            let linkContent = nsString.substring(with: match.range)
            
            if let href = extractAttribute(from: linkContent, attribute: "href") {
                // 提取链接文本
                if let textRange = linkContent.range(of: ">([^<]+)<", options: .regularExpression) {
                    var title = String(linkContent[textRange])
                    title = title.replacingOccurrences(of: ">", with: "")
                    title = title.replacingOccurrences(of: "<", with: "")
                    title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // 规范化 href（移除锚点）
                    let normalizedHref = href.components(separatedBy: "#").first ?? href
                    
                    entries.append(TOCEntry(title: title, href: normalizedHref, order: index))
                    DebugLogger.info("EPubParser: NAV条目[\(index + 1)] - \(title) -> \(normalizedHref)")
                }
            }
        }
        
        return entries
    }
    
    // MARK: - 章节解析
    
    private static func parseChapters(spineItems: [String], manifestMap: [String: String], baseURL: URL, tocEntries: [TOCEntry]) throws -> [Chapter] {
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
        
        for (index, idref) in spineItems.enumerated() {
            guard let href = manifestMap[idref] else {
                DebugLogger.warning("EPubParser: 跳过无效的spine项目: \(idref)")
                continue
            }
            
            // 解码 URL 编码的路径
            guard let decodedHref = href.removingPercentEncoding else {
                DebugLogger.warning("EPubParser: 无法解码href: \(href)")
                continue
            }
            
            let chapterURL = baseURL.appendingPathComponent(decodedHref)
            
            do {
                let htmlContent = try String(contentsOf: chapterURL, encoding: .utf8)
                let chapterContent = cleanHTML(htmlContent)
                
                // 尝试从TOC获取标题
                var chapterTitle: String?
                
                // 规范化 href 用于查找
                let normalizedHref = decodedHref.components(separatedBy: "#").first ?? decodedHref
                let fileName = (normalizedHref as NSString).lastPathComponent
                
                // 先尝试完整路径匹配
                if let tocTitle = hrefToTitle[normalizedHref] {
                    chapterTitle = tocTitle
                } else if let tocTitle = hrefToTitle[fileName] {
                    // 尝试只用文件名匹配
                    chapterTitle = tocTitle
                } else {
                    // 尝试从href中查找包含该文件名的条目
                    for (tocHref, tocTitle) in hrefToTitle {
                        if tocHref.hasSuffix(fileName) || tocHref.contains(fileName) {
                            chapterTitle = tocTitle
                            break
                        }
                    }
                }
                
                // 如果TOC中没有找到，尝试从HTML提取
                if chapterTitle == nil {
                    chapterTitle = extractChapterTitleFromHTML(htmlContent)
                }
                
                // 如果还是没有，使用默认标题
                let finalTitle = chapterTitle ?? "Chapter \(index + 1)"
                
                let chapter = Chapter(
                    title: finalTitle,
                    content: chapterContent,
                    order: index
                )
                
                chapters.append(chapter)
                DebugLogger.info("EPubParser: 解析章节[\(index + 1)] - \(finalTitle) (内容长度: \(chapterContent.count) 字符)")
                
            } catch {
                DebugLogger.warning("EPubParser: 无法读取章节文件: \(chapterURL.path), 错误: \(error.localizedDescription)")
            }
        }
        
        return chapters
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
