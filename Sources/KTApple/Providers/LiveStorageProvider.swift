import Foundation
import KTAppleCore

final class LiveStorageProvider: StorageProvider {
    func write(_ data: Data, to path: String) throws {
        try data.write(to: URL(fileURLWithPath: path))
    }

    func read(from path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func createDirectoryIfNeeded(at path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
    }
}
