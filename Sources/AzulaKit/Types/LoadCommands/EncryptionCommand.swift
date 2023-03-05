//
//  EncryptionCommand.swift
//  Azula
//
//  Created by Lilliana on 16/02/2023.
//

import MachO

struct EncryptionCommand: LoadCommand {
    typealias T = encryption_info_command_64
    
    let offset: Int
    let command: T
}
