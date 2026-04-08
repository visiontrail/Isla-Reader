import Foundation

public struct BatchJSONLWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = encoder
    }

    public func writeRows<T: Encodable>(_ rows: [T], to fileURL: URL) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            var output = Data()
            for row in rows {
                let lineData = try encoder.encode(row)
                output.append(lineData)
                output.append(0x0A)
            }
            try output.write(to: fileURL, options: .atomic)
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.ioFailure("Failed writing JSONL file at \(fileURL.path): \(error.localizedDescription)")
        }
    }
}

public struct BatchJSONFileWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    public func writeObject<T: Encodable>(_ object: T, to fileURL: URL) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let payload = try encoder.encode(object)
            try payload.write(to: fileURL, options: .atomic)
        } catch let error as BatchError {
            throw error
        } catch {
            throw BatchError.ioFailure("Failed writing JSON file at \(fileURL.path): \(error.localizedDescription)")
        }
    }
}
