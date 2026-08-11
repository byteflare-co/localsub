import Darwin
import Foundation

public enum NonReplacingFileWriter {
    public static func write(_ data: Data, to destination: URL) throws {
        let fd = Darwin.open(
            destination.path,
            O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard fd >= 0 else {
            if errno == EEXIST { throw CocoaError(.fileWriteFileExists) }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            Darwin.close(fd)
        }
        try data.withUnsafeBytes { bytes in
            guard var address = bytes.baseAddress else { return }
            var remaining = bytes.count
            while remaining > 0 {
                let written = Darwin.write(fd, address, remaining)
                guard written >= 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                remaining -= written
                address = address.advanced(by: written)
            }
        }
        guard Darwin.fsync(fd) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    static func canonicalDirectory(_ directory: URL) throws -> URL {
        guard let pointer = Darwin.realpath(directory.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        defer { Darwin.free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer), isDirectory: true)
    }
}
