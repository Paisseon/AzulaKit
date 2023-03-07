//
//  File.swift
//
//
//  Created by Lilliana on 06/03/2023.
//

import Foundation

struct Extractor {
    let target: Data
    let pretty: (any PrettyPrinter)?

    func extract<T>(
        at offset: Int = 0
    ) -> T? {
        let endOffset: Int = offset + MemoryLayout<T>.size

        guard endOffset < target.count else {
            pretty?.print(Log(text: String(format: "Offset 0x%X is out of bounds", endOffset), type: .error))
            return nil
        }

        let data: Data = target.subdata(in: offset ..< endOffset)

        return data.withUnsafeBytes { bytes in
            guard let pointer: UnsafePointer<T> = bytes.baseAddress?.bindMemory(to: T.self, capacity: 1) else {
                pretty?.print(Log(text: String(format: "Couldn't extract \(T.self) at 0x%X", offset), type: .error))
                return nil
            }

            return pointer.pointee
        }
    }

    func extractRaw(
        offset: Int,
        length: Int
    ) -> Data? {
        guard offset + length < target.count, length >= 0 else {
            pretty?.print(Log(text: String(format: "Offset 0x%X is out of bounds", offset + length), type: .error))
            return nil
        }

        return target.subdata(in: offset ..< offset + length)
    }
}
