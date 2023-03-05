//
//  LoadCommand.swift
//  Azula
//
//  Created by Lilliana on 16/02/2023.
//

protocol LoadCommand {
    associatedtype T
    
    var offset: Int { get }
    var command: T { get }
}
