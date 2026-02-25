import Foundation

/// Protocol abstracting file system operations for testability.
public protocol StorageProvider {
    func write(_ data: Data, to path: String) throws
    func read(from path: String) throws -> Data
    func fileExists(at path: String) -> Bool
    func createDirectoryIfNeeded(at path: String) throws
}
