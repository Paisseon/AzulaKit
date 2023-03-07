//
//  File.swift
//
//
//  Created by Lilliana on 06/03/2023.
//

import Foundation
import MachO

struct Remover {
    let pretty: (any PrettyPrinter)?
    let extractor: Extractor
    let patcher: Patcher

    func remove(
        _ payloads: [String]
    ) -> Bool {
        let dylibLoadCommands: [DylibCommand] = loadCommands.filter { $0 is DylibCommand }.map { $0 as! DylibCommand }
        var patches: [Patch] = []

        for dllc: DylibCommand in dylibLoadCommands {
            let lcStrOff: Int = .init(dllc.command.dylib.name.offset)
            let strOff: Int = dllc.offset + lcStrOff
            let len: Int = .init(dllc.command.cmdsize) - lcStrOff

            if let data: Data = extractor.extractRaw(offset: strOff, length: len),
               let curPath: String = .init(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters),
               payloads.contains(curPath)
            {
                pretty?.print(Log(text: "Found load command to remove", type: .info))
                
                // Creates a weak load command to an empty path
                // This means that it won't crash, and won't mess with injection either
                // Also doesn't try to load the real thing we remove, ofc

                var dylibCmd: dylib_command = dllc.command
                dylibCmd.cmd = LC_LOAD_WEAK_DYLIB
                
                let strData: Data = .init(repeating: 0, count: len)
                let cmdData: Data = .init(bytes: &dylibCmd, count: MemoryLayout<dylib_command>.size)

                patches.append(Patch(offset: strOff, data: strData))
                patches.append(Patch(offset: dllc.offset, data: cmdData))
            }
        }

        return patcher.patch(patches)
    }
}
