//
//  String.swift
//  Azula
//
//  Created by Lilliana on 16/02/2023.
//

import Foundation

extension String {
    init(
        withRawBytes rawBytes: (
            Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8,
            Int8, Int8, Int8, Int8
        )
    ) {
        var rawBytes = rawBytes
        let size: Int = MemoryLayout.size(ofValue: rawBytes)
        
        let string: String = withUnsafePointer(to: &rawBytes) { ptr in
            return ptr.withMemoryRebound(to: UInt8.self, capacity: size) {
                return String(cString: $0)
            }
        }
        
        self.init(string)
    }
    
    init(
        withData data: Data,
        at offset: Int,
        cmdSize: Int,
        cmdString: lc_str
    ) {
        let lcStrOff: Int = .init(cmdString.offset)
        let strOff: Int = offset + lcStrOff
        let len: Int = cmdSize - lcStrOff
        
        self = .init(data: data[strOff ..< strOff + len], encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
    }
}
