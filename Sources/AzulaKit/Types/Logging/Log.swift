//
//  Log.swift
//  Azula
//
//  Created by Lilliana on 05/03/2023.
//

import Foundation

public struct Log: Hashable, Identifiable {
    public let id: UUID = .init()
    public let text: String
    public let type: PrintType
    
    public init(
        text: String,
        type: PrintType
    ) {
        self.text = text
        self.type = type
    }
}
