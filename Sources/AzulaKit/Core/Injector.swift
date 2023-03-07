//
//  File.swift
//
//
//  Created by Lilliana on 06/03/2023.
//

import Foundation
import MachO

struct Injector {
    // MARK: Internal

    let pretty: (any PrettyPrinter)?
    let patcher: Patcher
    let extractor: Extractor

    func inject(
        _ payload: String,
        mh: MachHeader,
        isByteSwapped _: Bool
    ) -> Bool {
        let pathSize: Int = (payload.count & -8) + 8
        let payloadSize: Int = MemoryLayout<dylib_command>.size + pathSize
        let cmdOffset: UInt64 = UInt64(mh.offset + MemoryLayout<mach_header_64>.size)

        guard hasSpace(for: payload, header: mh.header) else {
            pretty?.print(Log(text: "Not enough space to inject payload", type: .error))
            return false
        }

        guard !isAlreadyInjected(payload) else {
            pretty?.print(Log(text: "Payload is already injected", type: .warn))
            return true
        }

        var dylibCmd: dylib_command = .init()
        var newHeader: mach_header_64 = mh.header

        pretty?.print(Log(text: "Creating load command for payload...", type: .info))

        dylibCmd.cmd = LC_LOAD_WEAK_DYLIB
        dylibCmd.cmdsize = UInt32(payloadSize)
        dylibCmd.dylib.name = lc_str(offset: UInt32(MemoryLayout<dylib_command>.size))

        pretty?.print(Log(text: "Updating header...", type: .info))

        newHeader.ncmds += 1
        newHeader.sizeofcmds += UInt32(payloadSize)

        if let index: Int = machHeaders.firstIndex(where: { $0.offset == mh.offset }) {
            machHeaders[index] = MachHeader(header: newHeader, offset: mh.offset)
        }

        let patches: [Patch] = [
            Patch(offset: mh.offset, data: Data(bytes: &newHeader, count: MemoryLayout<mach_header_64>.size)),
            Patch(offset: Int(cmdOffset) + Int(mh.header.sizeofcmds), data: Data(bytes: &dylibCmd, count: MemoryLayout<dylib_command>.size)),
            Patch(offset: nil, data: payload.data(using: .utf8)!),
        ]

        return patcher.patch(patches)
    }

    // MARK: Private

    private typealias CharTuple = (
        Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8,
        Int8, Int8, Int8, Int8
    )

    private func hasSpace(
        for payload: String,
        header: mach_header_64
    ) -> Bool {
        let pathSize: Int = (payload.count & -8) + 8
        let payloadSize: Int = MemoryLayout<dylib_command>.size + pathSize
        let segCommands: [SegmentCommand] = loadCommands.filter { $0 is SegmentCommand }.map { $0 as! SegmentCommand }

        for slc: SegmentCommand in segCommands {
            var segName: CharTuple = slc.command.segname

            if strncmp(&segName.0, "__TEXT", 15) == 0 {
                for i: UInt32 in 0 ..< slc.command.nsects {
                    let sectOffset: Int = slc.offset + MemoryLayout<segment_command_64>.size + MemoryLayout<section_64>.size * Int(i)

                    guard let sectCmd: section_64 = extractor.extract(at: sectOffset) else {
                        return false
                    }

                    var sectName: CharTuple = sectCmd.sectname

                    if strncmp(&sectName.0, "__text", 15) == 0 {
                        let space: UInt32 = sectCmd.offset - header.sizeofcmds - UInt32(MemoryLayout<mach_header_64>.size)
                        pretty?.print(Log(text: String(format: "Space available in arch: 0x%X", space), type: .info))
                        return space > payloadSize
                    }
                }
            }
        }

        pretty?.print(Log(text: "Couldn't find text section", type: .error))

        return false
    }

    private func isAlreadyInjected(
        _ payload: String
    ) -> Bool {
        let dylibLoadCommands: [DylibCommand] = loadCommands.filter { $0 is DylibCommand }.map { $0 as! DylibCommand }

        for dllc: DylibCommand in dylibLoadCommands {
            let lcStrOff: Int = .init(dllc.command.dylib.name.offset)
            let strOff: Int = dllc.offset + lcStrOff
            let len: Int = .init(dllc.command.cmdsize) - lcStrOff

            guard let data: Data = extractor.extractRaw(offset: strOff, length: len),
                  let curPath: String = .init(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            else {
                pretty?.print(Log(text: "Failed to read existing load command", type: .error))
                return false
            }

            guard curPath != payload else {
                return true
            }
            
            // TODO: This prints twice

            if curPath.components(separatedBy: "/").last == payload.components(separatedBy: "/").last {
                pretty?.print(Log(text: "Similar path found in target: \(curPath)", type: .warn))
            }
        }

        return false
    }
}
