import Foundation

// MARK: - MiniZip
//
// Minimal read-only ZIP reader. Supports Stored (method 0) and Deflate (method 8).
// Sufficient for EPUB archives (EPUB = ZIP + XHTML/OPF content).
//
// Usage:
//   let zip = try MiniZip(url: epubURL)
//   let data = try zip.extract(named: "META-INF/container.xml")
//   try zip.extractAll(to: destDirectory)

final class MiniZip {

    struct Entry {
        let name: String
        let method: UInt16           // 0 = stored, 8 = deflate
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    let entries: [Entry]

    init(url: URL) throws {
        let d = try Data(contentsOf: url, options: .mappedIfSafe)
        self.data = d
        self.entries = try MiniZip.parseEntries(from: d)
    }

    // MARK: - Extraction

    func extract(named name: String) throws -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        return try extract(entry)
    }

    func extract(_ entry: Entry) throws -> Data {
        let lhs = entry.localHeaderOffset
        guard lhs + 30 <= data.count,
              data.le32(at: lhs) == 0x04034b50 else { throw MiniZipError.corrupted }

        let fnLen    = Int(data.le16(at: lhs + 26))
        let extraLen = Int(data.le16(at: lhs + 28))
        let dataStart = lhs + 30 + fnLen + extraLen
        let dataEnd   = dataStart + entry.compressedSize
        guard dataEnd <= data.count else { throw MiniZipError.corrupted }

        let slice = data[dataStart ..< dataEnd]
        switch entry.method {
        case 0:  return Data(slice)
        case 8:  return try inflateRaw(Data(slice), expected: entry.uncompressedSize)
        default: throw MiniZipError.unsupportedMethod(entry.method)
        }
    }

    /// Writes every non-directory entry to `directory`, creating subdirectories as needed.
    /// Validates that resolved paths stay inside `directory` (prevents path traversal).
    func extractAll(to directory: URL) throws {
        let fm = FileManager.default
        let root = directory.standardized.path
        for entry in entries {
            guard !entry.name.hasSuffix("/") else { continue }
            let dest = directory.appendingPathComponent(entry.name).standardized
            guard dest.path.hasPrefix(root) else { continue } // path traversal — skip
            try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            let fileData = try extract(entry)
            try fileData.write(to: dest, options: .atomic)
        }
    }

    // MARK: - Central directory parsing

    private static func parseEntries(from data: Data) throws -> [Entry] {
        guard let eocd = findEOCD(in: data) else { throw MiniZipError.notAZip }

        let cdOffset = Int(data.le32(at: eocd + 16))
        let cdCount  = Int(data.le16(at: eocd + 8))
        guard cdOffset < data.count else { throw MiniZipError.corrupted }

        var entries: [Entry] = []
        var pos = cdOffset

        for _ in 0 ..< cdCount {
            guard pos + 46 <= data.count,
                  data.le32(at: pos) == 0x02014b50 else { break }

            let method    = data.le16(at: pos + 10)
            let csz       = Int(data.le32(at: pos + 20))
            let usz       = Int(data.le32(at: pos + 24))
            let fnLen     = Int(data.le16(at: pos + 28))
            let extraLen  = Int(data.le16(at: pos + 30))
            let commentLen = Int(data.le16(at: pos + 32))
            let lhOffset  = Int(data.le32(at: pos + 42))

            let nameEnd = pos + 46 + fnLen
            guard nameEnd <= data.count else { break }
            let name = String(data: data[(pos + 46) ..< nameEnd], encoding: .utf8)
                    ?? String(data: data[(pos + 46) ..< nameEnd], encoding: .isoLatin1)
                    ?? ""

            entries.append(Entry(name: name, method: method,
                                 compressedSize: csz, uncompressedSize: usz,
                                 localHeaderOffset: lhOffset))
            pos += 46 + fnLen + extraLen + commentLen
        }
        return entries
    }

    /// Scans from the end for the End-of-Central-Directory signature (0x06054b50).
    private static func findEOCD(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let searchFrom = max(0, data.count - 65_558)
        var i = data.count - 22
        while i >= searchFrom {
            if data[i] == 0x50 && data[i+1] == 0x4B &&
               data[i+2] == 0x05 && data[i+3] == 0x06 { return i }
            i -= 1
        }
        return nil
    }

    // MARK: - Raw DEFLATE decompression via zlib

    /// Max allocation per entry to prevent OOM from malicious declared sizes (100 MB).
    private static let maxDecompressedSize = 100 * 1024 * 1024

    private func inflateRaw(_ compressed: Data, expected: Int) throws -> Data {
        // Cap allocation: don't trust declared size blindly.
        // If expected is 0 or unreasonably large, use compressed * 4 as estimate.
        let capped = expected > 0 && expected <= MiniZip.maxDecompressedSize
            ? expected
            : min(compressed.count * 4, MiniZip.maxDecompressedSize)
        let outputSize = max(capped, 256)
        var output = Data(count: outputSize)
        var written = 0
        let status: Int32 = compressed.withUnsafeBytes { src in
            output.withUnsafeMutableBytes { dst in
                guard let inPtr  = src.baseAddress?.assumingMemoryBound(to: Bytef.self),
                      let outPtr = dst.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                    return Z_DATA_ERROR
                }
                var zs = z_stream()
                zs.next_in   = UnsafeMutablePointer(mutating: inPtr)
                zs.avail_in  = uInt(compressed.count)
                zs.next_out  = outPtr
                zs.avail_out = uInt(outputSize)
                // windowBits = -15 → raw DEFLATE (no zlib/gzip wrapper)
                inflateInit2_(&zs, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                let s = inflate(&zs, Z_FINISH)
                written = outputSize - Int(zs.avail_out)
                inflateEnd(&zs)
                return s
            }
        }
        // Z_STREAM_END = success. Z_BUF_ERROR with data = truncated (output too small).
        guard status == Z_STREAM_END else {
            throw MiniZipError.decompressionFailed(status)
        }
        return output.prefix(written)
    }
}

// MARK: - Errors

enum MiniZipError: Error, LocalizedError {
    case notAZip
    case corrupted
    case unsupportedMethod(UInt16)
    case decompressionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .notAZip:                   return "Файл не является ZIP-архивом"
        case .corrupted:                 return "Архив повреждён"
        case .unsupportedMethod(let m):  return "Неподдерживаемый метод сжатия: \(m)"
        case .decompressionFailed(let c): return "Ошибка распаковки (zlib код \(c))"
        }
    }
}

// MARK: - Data helpers (file-private)

fileprivate extension Data {
    /// Alignment-safe little-endian read (ZIP headers are byte-packed).
    func le16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }
    func le32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
        | UInt32(self[offset + 1]) << 8
        | UInt32(self[offset + 2]) << 16
        | UInt32(self[offset + 3]) << 24
    }
}
