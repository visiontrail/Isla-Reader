//
//  EPubParserEPUB3Tests.swift
//  LanReadTests
//

import Foundation
import Testing
import zlib
@testable import LanRead

struct EPubParserEPUB3Tests {
    @Test
    func parsesEPUB3NavOnlyWithoutSpineTOC() throws {
        let coverBytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let epubURL = try makeEPUBFile(
            contentOPF: """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="bookid">urn:uuid:test-epub3-nav-only</dc:identifier>
                <dc:title>EPUB3 Nav Only</dc:title>
                <dc:creator>LanRead QA</dc:creator>
                <dc:language>en</dc:language>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="cover" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
                <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
                <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="ch1"/>
                <itemref idref="ch2"/>
              </spine>
            </package>
            """,
            additionalEntries: [
                ZIPEntry(
                    path: "OEBPS/nav.xhtml",
                    data: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <html xmlns="http://www.w3.org/1999/xhtml">
                          <body>
                            <nav role="doc-toc">
                              <ol>
                                <li><a href="text/ch1.xhtml#s1">Chapter One</a></li>
                                <li><a href="text/ch2.xhtml">Chapter Two</a></li>
                              </ol>
                            </nav>
                          </body>
                        </html>
                        """.utf8
                    )
                ),
                ZIPEntry(
                    path: "OEBPS/text/ch1.xhtml",
                    data: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <html xmlns="http://www.w3.org/1999/xhtml">
                          <head><title>Chapter One Title</title></head>
                          <body>
                            <h1 id="s1">Chapter One</h1>
                            <p>Hello EPUB3.</p>
                            <img src="../images/cover.jpg" alt="cover"/>
                          </body>
                        </html>
                        """.utf8
                    )
                ),
                ZIPEntry(
                    path: "OEBPS/text/ch2.xhtml",
                    data: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <html xmlns="http://www.w3.org/1999/xhtml">
                          <head><title>Chapter Two Title</title></head>
                          <body>
                            <h1>Chapter Two</h1>
                            <p>Second chapter content.</p>
                          </body>
                        </html>
                        """.utf8
                    )
                ),
                ZIPEntry(path: "OEBPS/images/cover.jpg", data: coverBytes)
            ]
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let metadata = try EPubParser.parseEPub(from: epubURL)

        #expect(metadata.title == "EPUB3 Nav Only")
        #expect(metadata.author == "LanRead QA")
        #expect(metadata.language == "en")
        #expect(metadata.chapters.count == 2)
        #expect(metadata.tocItems.count == 2)
        #expect(metadata.tocItems[0].title == "Chapter One")
        #expect(metadata.tocItems[0].chapterIndex == 0)
        #expect(metadata.tocItems[1].chapterIndex == 1)
        #expect(metadata.coverImageData == coverBytes)
        #expect(metadata.chapters[0].htmlContent.contains("data:image/jpeg;base64,"))
    }

    @Test
    func keepsEPUB2NCXTOCBehavior() throws {
        let epubURL = try makeEPUBFile(
            contentOPF: """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="bookid">urn:uuid:test-epub2-ncx</dc:identifier>
                <dc:title>EPUB2 NCX</dc:title>
                <dc:creator>LanRead QA</dc:creator>
                <dc:language>en</dc:language>
                <meta name="cover" content="cover-image"/>
              </metadata>
              <manifest>
                <item id="cover-image" href="images/cover.jpg" media-type="image/jpeg"/>
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
                <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine toc="ncx">
                <itemref idref="ch1"/>
                <itemref idref="ch2"/>
              </spine>
            </package>
            """,
            additionalEntries: [
                ZIPEntry(
                    path: "OEBPS/toc.ncx",
                    data: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                          <navMap>
                            <navPoint id="n1" playOrder="1">
                              <navLabel><text>First Chapter</text></navLabel>
                              <content src="text/ch1.xhtml"/>
                            </navPoint>
                            <navPoint id="n2" playOrder="2">
                              <navLabel><text>Second Chapter</text></navLabel>
                              <content src="text/ch2.xhtml"/>
                            </navPoint>
                          </navMap>
                        </ncx>
                        """.utf8
                    )
                ),
                ZIPEntry(
                    path: "OEBPS/text/ch1.xhtml",
                    data: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <html xmlns="http://www.w3.org/1999/xhtml"><body><h1>A</h1><p>One</p></body></html>
                        """.utf8
                    )
                ),
                ZIPEntry(
                    path: "OEBPS/text/ch2.xhtml",
                    data: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <html xmlns="http://www.w3.org/1999/xhtml"><body><h1>B</h1><p>Two</p></body></html>
                        """.utf8
                    )
                ),
                ZIPEntry(path: "OEBPS/images/cover.jpg", data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
            ]
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let metadata = try EPubParser.parseEPub(from: epubURL)

        #expect(metadata.title == "EPUB2 NCX")
        #expect(metadata.chapters.count == 2)
        #expect(metadata.tocItems.count == 2)
        #expect(metadata.tocItems[0].title == "First Chapter")
        #expect(metadata.tocItems[0].chapterIndex == 0)
        #expect(metadata.tocItems[1].chapterIndex == 1)
        #expect(metadata.coverImageData != nil)
    }

    @Test
    func parsesEPUB3DeflatedArchiveWithHashCoverIdentifier() throws {
        let coverBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let epubURL = try makeEPUBFile(
            contentOPF: """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="bookid">urn:uuid:test-epub3-deflated</dc:identifier>
                <dc:title>EPUB3 Deflated</dc:title>
                <dc:creator>LanRead QA</dc:creator>
                <dc:language>en</dc:language>
                <meta property="cover-image">#cover-img</meta>
              </metadata>
              <manifest>
                <item id="nav" href="OPS/nav-doc.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="cover-img" href="OPS/images/cover.png" media-type="image/png"/>
                <item id="c1" href="OPS/text/ch1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="c1"/>
              </spine>
            </package>
            """,
            additionalEntries: [
                ZIPEntry(
                    path: "OEBPS/OPS/nav-doc.xhtml",
                    data: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                          <body>
                            <nav epub:type="toc">
                              <ol>
                                <li><a href="text/ch1.xhtml">Single Chapter</a></li>
                              </ol>
                            </nav>
                          </body>
                        </html>
                        """.utf8
                    ),
                    compression: .deflated
                ),
                ZIPEntry(
                    path: "OEBPS/OPS/text/ch1.xhtml",
                    data: Data(
                        """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <html xmlns="http://www.w3.org/1999/xhtml">
                          <head><title>Single Chapter</title></head>
                          <body>
                            <h1>Single Chapter</h1>
                            <p>Compressed payload chapter.</p>
                            <img src="../images/cover.png" alt="cover"/>
                          </body>
                        </html>
                        """.utf8
                    ),
                    compression: .deflated
                ),
                ZIPEntry(path: "OEBPS/OPS/images/cover.png", data: coverBytes, compression: .deflated)
            ]
        )
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let metadata = try EPubParser.parseEPub(from: epubURL)

        #expect(metadata.title == "EPUB3 Deflated")
        #expect(metadata.chapters.count == 1)
        #expect(metadata.tocItems.count == 1)
        #expect(metadata.tocItems[0].title == "Single Chapter")
        #expect(metadata.tocItems[0].chapterIndex == 0)
        #expect(metadata.coverImageData == coverBytes)
        #expect(metadata.chapters[0].htmlContent.contains("data:image/png;base64,"))
    }
}

private extension EPubParserEPUB3Tests {
    struct ZIPEntry {
        enum CompressionMethod {
            case stored
            case deflated
        }

        let path: String
        let data: Data
        let compression: CompressionMethod

        init(path: String, data: Data, compression: CompressionMethod = .stored) {
            self.path = path
            self.data = data
            self.compression = compression
        }
    }

    enum ZIPBuildError: Error {
        case deflateInitFailed
        case deflateFailed(Int32)
    }

    func makeEPUBFile(contentOPF: String, additionalEntries: [ZIPEntry]) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")

        var entries: [ZIPEntry] = [
            ZIPEntry(path: "mimetype", data: Data("application/epub+zip".utf8)),
            ZIPEntry(
                path: "META-INF/container.xml",
                data: Data(
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                      <rootfiles>
                        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
                      </rootfiles>
                    </container>
                    """.utf8
                )
            ),
            ZIPEntry(path: "OEBPS/content.opf", data: Data(contentOPF.utf8))
        ]
        entries.append(contentsOf: additionalEntries)

        let archiveData = try makeZIP(entries: entries)
        try archiveData.write(to: tempURL, options: .atomic)
        return tempURL
    }

    func makeZIP(entries: [ZIPEntry]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let localHeaderOffset = UInt32(archive.count)
            let pathData = Data(entry.path.utf8)
            let crc = crc32(of: entry.data)
            let payload = try compressedPayload(for: entry)
            let compressedSize = UInt32(payload.count)
            let uncompressedSize = UInt32(entry.data.count)
            let method: UInt16 = entry.compression == .deflated ? 8 : 0

            appendUInt32(0x04034b50, to: &archive) // local file header
            appendUInt16(20, to: &archive) // version needed to extract
            appendUInt16(0, to: &archive) // general purpose bit flag
            appendUInt16(method, to: &archive) // compression method
            appendUInt16(0, to: &archive) // file time
            appendUInt16(0, to: &archive) // file date
            appendUInt32(crc, to: &archive)
            appendUInt32(compressedSize, to: &archive)
            appendUInt32(uncompressedSize, to: &archive)
            appendUInt16(UInt16(pathData.count), to: &archive)
            appendUInt16(0, to: &archive) // extra length
            archive.append(pathData)
            archive.append(payload)

            appendUInt32(0x02014b50, to: &centralDirectory) // central dir header
            appendUInt16(20, to: &centralDirectory) // version made by
            appendUInt16(20, to: &centralDirectory) // version needed to extract
            appendUInt16(0, to: &centralDirectory) // general purpose bit flag
            appendUInt16(method, to: &centralDirectory) // compression method
            appendUInt16(0, to: &centralDirectory) // file time
            appendUInt16(0, to: &centralDirectory) // file date
            appendUInt32(crc, to: &centralDirectory)
            appendUInt32(compressedSize, to: &centralDirectory)
            appendUInt32(uncompressedSize, to: &centralDirectory)
            appendUInt16(UInt16(pathData.count), to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory) // extra length
            appendUInt16(0, to: &centralDirectory) // comment length
            appendUInt16(0, to: &centralDirectory) // disk number start
            appendUInt16(0, to: &centralDirectory) // internal attributes
            appendUInt32(entry.path.hasSuffix("/") ? 0x10 : 0, to: &centralDirectory) // external attrs
            appendUInt32(localHeaderOffset, to: &centralDirectory)
            centralDirectory.append(pathData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        appendUInt32(0x06054b50, to: &archive) // end of central directory
        appendUInt16(0, to: &archive) // number of this disk
        appendUInt16(0, to: &archive) // number of the disk with start of central directory
        appendUInt16(UInt16(entries.count), to: &archive) // total entries on this disk
        appendUInt16(UInt16(entries.count), to: &archive) // total entries
        appendUInt32(UInt32(centralDirectory.count), to: &archive) // central directory size
        appendUInt32(centralDirectoryOffset, to: &archive) // central directory offset
        appendUInt16(0, to: &archive) // comment length

        return archive
    }

    func compressedPayload(for entry: ZIPEntry) throws -> Data {
        switch entry.compression {
        case .stored:
            return entry.data
        case .deflated:
            return try deflateRaw(entry.data)
        }
    }

    func deflateRaw(_ data: Data) throws -> Data {
        if data.isEmpty {
            return Data()
        }

        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw ZIPBuildError.deflateInitFailed
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16_384

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
                    let flushMode: Int32 = stream.avail_in == 0 ? Z_FINISH : Z_NO_FLUSH
                    return deflate(&stream, flushMode)
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }

                if status == Z_STREAM_END {
                    return status
                }
                if status != Z_OK {
                    return status
                }
            }
        }

        guard finalStatus == Z_STREAM_END else {
            throw ZIPBuildError.deflateFailed(finalStatus)
        }

        return output
    }

    func crc32(of data: Data) -> UInt32 {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return UInt32(zlib.crc32(0, nil, 0))
            }
            return UInt32(zlib.crc32(0, baseAddress, uInt(rawBuffer.count)))
        }
    }

    func appendUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
