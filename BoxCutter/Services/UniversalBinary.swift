import Foundation

/// Reads only bounded FAT headers; estimating savings never executes or changes app code.
enum UniversalBinary {
    nonisolated static func estimatedSavings(in bundle: URL, keeping architecture: BinaryArchitecture) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true, values.isRegularFile == true,
                  let size = values.fileSize, size >= 8,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            // At most 64 fat_arch_64 records, plus the 8-byte header.
            guard let header = try? handle.read(upToCount: 8 + 64 * 32) else { continue }
            total += removableBytes(in: header, fileSize: UInt64(size), keeping: architecture)
        }
        return total
    }

    nonisolated static func removableBytes(
        in data: Data, fileSize: UInt64, keeping architecture: BinaryArchitecture
    ) -> Int64 {
        guard data.count >= 8 else { return 0 }
        let magic = integer(data, at: 0, bytes: 4, littleEndian: false)
        let littleEndian: Bool
        let wide: Bool
        switch magic {
        case 0xcafebabe: (littleEndian, wide) = (false, false)
        case 0xbebafeca: (littleEndian, wide) = (true, false)
        case 0xcafebabf: (littleEndian, wide) = (false, true)
        case 0xbfbafeca: (littleEndian, wide) = (true, true)
        default: return 0
        }
        let count = integer(data, at: 4, bytes: 4, littleEndian: littleEndian)
        guard count > 1, count <= 64 else { return 0 }
        let stride = wide ? 32 : 20
        let headerSize = 8 + Int(count) * stride
        guard data.count >= headerSize, fileSize >= UInt64(headerSize) else { return 0 }
        let nativeCPU: UInt64 = architecture == .arm64 ? 0x0100000c : 0x01000007
        var nativeSizes: [UInt64] = []
        var ranges: [Range<UInt64>] = []
        for index in 0..<Int(count) {
            let base = 8 + index * stride
            let cpu = integer(data, at: base, bytes: 4, littleEndian: littleEndian)
            let offset = integer(data, at: base + 8, bytes: wide ? 8 : 4, littleEndian: littleEndian)
            let size = integer(data, at: base + (wide ? 16 : 12), bytes: wide ? 8 : 4, littleEndian: littleEndian)
            guard offset >= UInt64(headerSize), offset <= fileSize, size > 0, size <= fileSize - offset else { return 0 }
            ranges.append(offset..<(offset + size))
            if cpu == nativeCPU { nativeSizes.append(size) }
        }
        let ordered = ranges.sorted { $0.lowerBound < $1.lowerBound }
        for index in 1..<ordered.count where ordered[index - 1].upperBound > ordered[index].lowerBound {
            return 0
        }
        // ditto's subtype choice can vary with multiple slices for the same CPU.
        // Do not promise a saving unless the retained slice is unambiguous.
        guard nativeSizes.count == 1, fileSize <= UInt64(Int64.max) else { return 0 }
        return Int64(fileSize - nativeSizes[0])
    }

    nonisolated private static func integer(_ data: Data, at offset: Int, bytes: Int, littleEndian: Bool) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<bytes {
            let byte = data[offset + (littleEndian ? bytes - 1 - index : index)]
            result = (result << 8) | UInt64(byte)
        }
        return result
    }
}
