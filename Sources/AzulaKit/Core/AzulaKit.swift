//
//  AzulaKit.swift
//  AzulaKit
//
//  Created by Lilliana on 16/02/2023.
//

import Foundation
import MachO

private var loadCommands: [any LoadCommand] = []
private var machHeaders: [MachHeader] = []

// MARK: - AzulaKit

@available(macOS 11, iOS 14, *)
public struct AzulaKit {
    // MARK: Lifecycle

    public init(
        dylibs _dylibs: [String],
        remove: [String],
        targetURL url: URL,
        printer: any PrettyPrinter
    ) {
        targetURL = url
        dylibs = _dylibs
        removed = remove
        pretty = printer

        do {
            let bakURL: URL = .init(fileURLWithPath: "./" + url.lastPathComponent + ".bak")

            if access(bakURL.path, F_OK) != 0 {
                try FileManager.default.copyItem(at: url, to: bakURL)
            }
        } catch {
            pretty.print(error.localizedDescription, type: .warn)
            pretty.print("Couldn't create backup of target", type: .warn)
        }

        guard let data: Data = try? .init(contentsOf: url) else {
            pretty.print("Couldn't read target", type: .warn)
            exit(1)
        }

        target = data

        let fatHeader: fat_header = target.extract()

        switch fatHeader.magic {
            case FAT_CIGAM,
                 FAT_CIGAM_64,
                 FAT_MAGIC,
                 FAT_MAGIC_64:
                let archCount: UInt32 = _OSSwapInt32(fatHeader.nfat_arch)
                var offset: Int = MemoryLayout<fat_header>.size

                pretty.print("Target has \(archCount) arches", type: .info)

                for i: UInt32 in 0 ..< archCount {
                    if i > 0 {
                        offset += MemoryLayout<fat_arch>.size
                    }

                    let arch: fat_arch = target.extract(at: offset)
                    let archOffset: UInt32 = _OSSwapInt32(arch.offset)
                    let header: mach_header_64 = target.extract(at: Int(archOffset))

                    machHeaders.append(MachHeader(header: header, offset: Int(archOffset)))
                }
            default:
                pretty.print("Target has 1 arch", type: .info)

                let header: mach_header_64 = target.extract()
                machHeaders.append(MachHeader(header: header, offset: 0))
        }

        for mh: MachHeader in machHeaders {
            let isByteSwapped: Bool

            switch mh.header.magic {
                case MH_MAGIC,
                     MH_MAGIC_64:
                    isByteSwapped = false
                case MH_CIGAM,
                     MH_CIGAM_64:
                    isByteSwapped = true
                default:
                    pretty.print(String(format: "Unknown MachO magic: 0x%X", mh.header.magic), type: .warn)
                    isByteSwapped = true
            }

            pretty.print("Getting load commands for \(mh.header.cputype == CPU_TYPE_ARM64 ? "arm64" : "x86_64")...", type: .info)

            loadCommands.append(contentsOf: getLoadCommands(at: mh.offset, isByteSwapped: isByteSwapped))
        }
    }

    // MARK: Public

    public func inject() -> Bool {
        guard !isEncrypted() else {
            pretty.print("Binary is encrypted, you must decrypt", type: .error)
            return false
        }

        for payload: String in dylibs {
            for mh: MachHeader in machHeaders {
                let isByteSwapped: Bool

                switch mh.header.magic {
                    case MH_MAGIC,
                         MH_MAGIC_64:
                        isByteSwapped = false
                    case MH_CIGAM,
                         MH_CIGAM_64:
                        isByteSwapped = true
                    default:
                        pretty.print(String(format: "Unknown MachO magic: 0x%X", mh.header.magic), type: .error)
                        return false
                }

                pretty.print("Current arch is \(mh.header.cputype == CPU_TYPE_ARM64 ? "arm64" : "x86_64")", type: .info)

                guard _inject(payload, mh: mh, isByteSwapped: isByteSwapped) else {
                    return false
                }
            }

            pretty.print("Injected \(payload.components(separatedBy: "/").last ?? "")", type: .info)
        }

        return true
    }

    public func remove() -> Bool {
        for payload: String in removed {
            for mh in machHeaders {
                guard _remove(payload, for: mh) else {
                    return false
                }
            }
        }

        return true
    }

    public func slice() -> Bool {
        let signatureLoadCommands: [SignatureCommand] = loadCommands.filter { $0 is SignatureCommand }.map { $0 as! SignatureCommand }
        var patches: [Patch] = []
        var strip: Int = 0x0000_1337

        for cslc: SignatureCommand in signatureLoadCommands {
            patches.append(Patch(offset: cslc.offset, data: Data(bytes: &strip, count: 4)))
        }

        return patch(patches)
    }

    // MARK: Private

    private typealias CharTuple = (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8)

    private let dylibs: [String]
    private let pretty: any PrettyPrinter
    private let removed: [String]
    private let target: Data
    private let targetURL: URL

    private func _inject(
        _ payload: String,
        mh: MachHeader,
        isByteSwapped _: Bool
    ) -> Bool {
        let pathSize: Int = (payload.count & -8) + 8
        let payloadSize: Int = MemoryLayout<dylib_command>.size + pathSize
        let cmdOffset: UInt64 = UInt64(mh.offset + MemoryLayout<mach_header_64>.size)

        guard hasSpace(for: payload, header: mh.header) else {
            pretty.print("Not enough space to inject payload", type: .error)
            return false
        }

        guard !isAlreadyInjected(payload) else {
            pretty.print("Payload is already injected", type: .error)
            return false
        }

        var dylibCmd: dylib_command = .init()
        var newHeader: mach_header_64 = mh.header

        pretty.print("Creating load command for payload...", type: .info)

        dylibCmd.cmd = LC_LOAD_WEAK_DYLIB
        dylibCmd.cmdsize = UInt32(payloadSize)
        dylibCmd.dylib.name = lc_str(offset: UInt32(MemoryLayout<dylib_command>.size))

        pretty.print("Updating header...", type: .info)

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

        return patch(patches)
    }

    private func _remove(
        _ payload: String,
        for mh: MachHeader
    ) -> Bool {
        let dylibLoadCommands: [DylibCommand] = loadCommands.filter { $0 is DylibCommand }.map { $0 as! DylibCommand }
        var patches: [Patch] = []

        for dllc: DylibCommand in dylibLoadCommands {
            if String(withData: target, at: dllc.offset, cmdSize: dllc.cmdSize, cmdString: dllc.command.dylib.name) == payload {
                pretty.print("Found load command to remove", type: .info)

                let start = dllc.offset
                let size = Int(dllc.cmdSize)
                let end = start + size

                var newHeader: mach_header_64 = mh.header
                newHeader.ncmds -= 1
                newHeader.sizeofcmds -= UInt32(dllc.command.cmdsize)

                if let index: Int = machHeaders.firstIndex(where: { $0.offset == mh.offset }) {
                    machHeaders[index] = MachHeader(header: newHeader, offset: mh.offset)
                }

                let cmdRange: Range<Data.Index> = .init(NSRange(location: start + size, length: end - start - size))!
                let cmdData: Data = target.subdata(in: cmdRange) + Data(repeating: 0, count: size)
                let nhData: Data = .init(bytes: &newHeader, count: MemoryLayout<mach_header_64>.size)

                patches.append(Patch(offset: mh.offset, data: nhData))
                patches.append(Patch(offset: start, data: cmdData))
            }
        }

        return patch(patches)
    }

    private func getLoadCommands(
        at _offset: Int,
        isByteSwapped: Bool
    ) -> [any LoadCommand] {
        let header: mach_header_64 = target.extract()
        var offset: Int = _offset + MemoryLayout.size(ofValue: header)
        var ret: [any LoadCommand] = []

        for _ in 0 ..< header.ncmds {
            let loadCommand: load_command = target.extract(at: offset)
            let myLoadCommand: any LoadCommand

            switch loadCommand.cmd {
                case LC_LOAD_WEAK_DYLIB,
                     UInt32(LC_LOAD_DYLIB):
                    var command: dylib_command = target.extract(at: offset)

                    if isByteSwapped {
                        swap_dylib_command(&command, NXByteOrder(rawValue: 0))
                    }

                    myLoadCommand = DylibCommand(offset: offset, command: command, cmdSize: Int(loadCommand.cmdsize))

                case UInt32(LC_ENCRYPTION_INFO_64):
                    var command: encryption_info_command_64 = target.extract(at: offset)

                    if isByteSwapped {
                        swap_encryption_command_64(&command, NXByteOrder(rawValue: 0))
                    }

                    myLoadCommand = EncryptionCommand(offset: offset, command: command)

                case UInt32(LC_CODE_SIGNATURE):
                    var command: linkedit_data_command = target.extract(at: offset)

                    if isByteSwapped {
                        swap_linkedit_data_command(&command, NXByteOrder(rawValue: 0))
                    }

                    myLoadCommand = SignatureCommand(offset: offset, command: command)

                case UInt32(LC_SEGMENT_64):
                    var command: segment_command_64 = target.extract(at: offset)

                    if isByteSwapped {
                        swap_segment_command_64(&command, NXByteOrder(rawValue: 0))
                    }

                    myLoadCommand = SegmentCommand(offset: offset, command: command)

                default:
                    myLoadCommand = UnknownCommand(offset: offset, rawValue: loadCommand.cmd, command: loadCommand)
            }

            ret.append(myLoadCommand)
            offset += Int(loadCommand.cmdsize)
        }

        return ret
    }

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
                    let sectCmd: section_64 = target.extract(at: sectOffset)
                    var sectName: CharTuple = sectCmd.sectname

                    if strncmp(&sectName.0, "__text", 15) == 0 {
                        let space: UInt32 = sectCmd.offset - header.sizeofcmds - UInt32(MemoryLayout<mach_header_64>.size)
                        pretty.print(String(format: "Space available in arch: 0x%X", space), type: .info)
                        return space > payloadSize
                    }
                }
            }
        }

        pretty.print("Couldn't find text section", type: .error)

        return false
    }

    private func isAlreadyInjected(
        _ payload: String
    ) -> Bool {
        let dylibLoadCommands: [DylibCommand] = loadCommands.filter { $0 is DylibCommand }.map { $0 as! DylibCommand }

        for dllc: DylibCommand in dylibLoadCommands {
            let curPath: String = .init(
                withData: target,
                at: dllc.offset,
                cmdSize: dllc.cmdSize,
                cmdString: dllc.command.dylib.name
            )

            guard curPath != payload else {
                return true
            }

            if curPath.components(separatedBy: "/").last == payload.components(separatedBy: "/").last {
                pretty.print("Similar path found in target: \(curPath)", type: .warn)
            }
        }

        return false
    }

    private func isEncrypted() -> Bool {
        let encLoadCommands: [EncryptionCommand] = loadCommands.filter { $0 is EncryptionCommand }.map { $0 as! EncryptionCommand }

        for elc: EncryptionCommand in encLoadCommands {
            guard elc.command.cryptid != 1 else {
                return true
            }
        }

        return false
    }

    private func patch(
        _ patches: [Patch]
    ) -> Bool {
        guard let fileHandle: FileHandle = try? .init(forWritingTo: targetURL) else {
            pretty.print("Couldn't get writing handle for target", type: .error)
            return false
        }

        guard !patches.isEmpty else {
            pretty.print("No patches", type: .warn)
            return false
        }

        do {
            pretty.print("Patching target...", type: .info)

            for patch in patches {
                if let offset: Int = patch.offset {
                    try fileHandle.seek(toOffset: UInt64(offset))
                }

                try fileHandle.write(contentsOf: patch.data)
            }

            try fileHandle.close()
        } catch {
            pretty.print(error.localizedDescription, type: .error)
            return false
        }

        return true
    }
}
