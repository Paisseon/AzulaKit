//
//  UnknownCommand.swift
//  Azula
//
//  Created by Lilliana on 16/02/2023.
//

import MachO

struct UnknownCommand: LoadCommand {
    typealias T = load_command
    
    let offset: Int
    let rawValue: UInt32
    let command: T
}
