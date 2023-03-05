//
//  Log.swift
//  Azula
//
//  Created by Lilliana on 05/03/2023.
//

public struct Log: Hashable {
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
