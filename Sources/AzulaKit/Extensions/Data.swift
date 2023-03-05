//
//  Data.swift
//  Azula
//
//  Created by Lilliana on 16/02/2023.
//

import Foundation

extension Data {
    func extract<T>(
        at offset: Int = 0
    ) -> T {
        let data: Data = subdata(in: offset ..< offset + MemoryLayout<T>.size)
        
        return data.withUnsafeBytes { dataBytes in
            let pointer: UnsafePointer<T> = dataBytes.baseAddress!.bindMemory(to: T.self, capacity: 1)
            return pointer.pointee
        }
    }
    
    func safeExtract<T>(
        at offset: Int = 0
    ) -> T? {
        guard offset + MemoryLayout<T>.size < count else {
            return nil
        }
        
        let data: Data = subdata(in: offset ..< offset + MemoryLayout<T>.size)
        
        return data.withUnsafeBytes { dataBytes in
            guard let pointer: UnsafePointer<T> = dataBytes.baseAddress?.bindMemory(to: T.self, capacity: 1) else {
                return nil
            }
            
            return pointer.pointee
        }
    }
}
