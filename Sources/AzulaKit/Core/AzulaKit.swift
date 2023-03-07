//
//  AzulaKit.swift
//  AzulaKit
//
//  Created by Lilliana on 16/02/2023.
//

import Foundation
import MachO

var loadCommands: [any LoadCommand] = []
var machHeaders: [MachHeader] = []

// MARK: - AzulaKit

public struct AzulaKit {
    // MARK: Lifecycle

    public init(
        dylibs _dylibs: [String],
        remove: [String],
        targetURL url: URL,
        printer: (any PrettyPrinter)? = nil
    ) {
        // Initialise all the variables

        dylibs = _dylibs
        removed = remove
        pretty = printer
        targetURL = url
        target = (try? .init(contentsOf: url)) ?? Data()
        extractor = Extractor(target: target, pretty: pretty)
        patcher = Patcher(targetURL: url, pretty: pretty)
        injector = Injector(pretty: pretty, patcher: patcher, extractor: extractor)
        remover = Remover(pretty: pretty, extractor: extractor, patcher: patcher)

        // Parse the target binary to get headers and load commands

        guard let fatHeader: fat_header = extractor.extract() else {
            return
        }

        switch fatHeader.magic {
            case FAT_CIGAM,
                 FAT_CIGAM_64,
                 FAT_MAGIC,
                 FAT_MAGIC_64:
                let archCount: UInt32 = _OSSwapInt32(fatHeader.nfat_arch)
                var offset: Int = MemoryLayout<fat_header>.size

                pretty?.print(Log(text: "Target has \(archCount) arches", type: .info))

                for i: UInt32 in 0 ..< archCount {
                    if i > 0 {
                        offset += MemoryLayout<fat_arch>.size
                    }

                    let arch: fat_arch = extractor.extract(at: offset)!
                    let archOffset: Int = .init(_OSSwapInt32(arch.offset))
                    let header: mach_header_64 = extractor.extract(at: archOffset)!

                    machHeaders.append(MachHeader(header: header, offset: archOffset))
                }
            default:
                pretty?.print(Log(text: "Target has 1 arch", type: .info))

                let header: mach_header_64 = extractor.extract()!
                machHeaders.append(MachHeader(header: header, offset: 0))
        }
        
        // Doing this twice on fat binaries slows things down noticably
        // TODO: Maybe calculate arch offset difference and iterate through loadCommands?

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
                    pretty?.print(Log(text: String(format: "Unknown MachO magic: 0x%X", mh.header.magic), type: .warn))
                    isByteSwapped = true
            }

            pretty?.print(Log(text: "Getting load commands for \(getArchName(for: mh.header))...", type: .info))
            loadCommands.append(contentsOf: getLoadCommands(for: mh, isByteSwapped: isByteSwapped))
        }
    }

    // MARK: Public

    @discardableResult
    public func inject() -> Bool {
        guard !isEncrypted() else {
            pretty?.print(Log(text: "Binary is encrypted, you must decrypt", type: .error))
            return false
        }

        // I know that using Algorithms.product() would be cleaner here, but I want to avoid dependencies

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
                        pretty?.print(Log(text: String(format: "Unknown MachO magic: 0x%X", mh.header.magic), type: .error))
                        return false
                }

                pretty?.print(Log(text: "Current arch is \(getArchName(for: mh.header))", type: .info))

                guard injector.inject(payload, mh: mh, isByteSwapped: isByteSwapped) else {
                    return false
                }
            }

            pretty?.print(Log(text: "Injected \(payload.components(separatedBy: "/").last ?? "???")", type: .info))
        }

        return true
    }

    @discardableResult
    public func remove() -> Bool {
        remover.remove(removed)
    }

    @discardableResult
    public func slice() -> Bool {
        let signatureLoadCommands: [SignatureCommand] = loadCommands.filter { $0 is SignatureCommand }.map { $0 as! SignatureCommand }
        var patches: [Patch] = []
        var strip: Int = 0x0000_1337

        for cslc: SignatureCommand in signatureLoadCommands {
            patches.append(Patch(offset: cslc.offset, data: Data(bytes: &strip, count: 4)))
        }

        return patcher.patch(patches)
    }

    // MARK: Private

    private let dylibs: [String]
    private let pretty: (any PrettyPrinter)?
    private let removed: [String]
    private let target: Data
    private let targetURL: URL
    private let injector: Injector
    private let patcher: Patcher
    private let remover: Remover
    private let extractor: Extractor

    // Covers the three architectures which Azula supports
    
    private func getArchName(
        for header: mach_header_64
    ) -> String {
        if header.cputype != CPU_TYPE_ARM64 {
            return "x86_64"
        }

        return header.cpusubtype == CPU_SUBTYPE_ARM64E ? "arm64e" : "arm64"
    }

    private func getLoadCommands(
        for mh: MachHeader,
        isByteSwapped: Bool
    ) -> [any LoadCommand] {
        guard let header: mach_header_64 = extractor.extract() else {
            return []
        }

        var offset: Int = mh.offset + MemoryLayout.size(ofValue: header)
        var ret: [any LoadCommand] = []

        for _ in 0 ..< header.ncmds {
            guard let loadCommand: load_command = extractor.extract(at: offset) else {
                pretty?.print(Log(text: "Offset for load command is out-of-bounds", type: .error))
                return ret
            }

            let myLoadCommand: any LoadCommand

            switch loadCommand.cmd {
                case LC_LOAD_WEAK_DYLIB,
                     UInt32(LC_LOAD_DYLIB):
                    var command: dylib_command = extractor.extract(at: offset)!

                    if isByteSwapped {
                        swap_dylib_command(&command, NXByteOrder(rawValue: 0))
                    }

                    myLoadCommand = DylibCommand(offset: offset, command: command, mh: mh)

                case UInt32(LC_ENCRYPTION_INFO_64):
                    var command: encryption_info_command_64 = extractor.extract(at: offset)!

                    if isByteSwapped {
                        swap_encryption_command_64(&command, NXByteOrder(rawValue: 0))
                    }

                    myLoadCommand = EncryptionCommand(offset: offset, command: command)

                case UInt32(LC_CODE_SIGNATURE):
                    var command: linkedit_data_command = extractor.extract(at: offset)!

                    if isByteSwapped {
                        swap_linkedit_data_command(&command, NXByteOrder(rawValue: 0))
                    }

                    myLoadCommand = SignatureCommand(offset: offset, command: command)

                case UInt32(LC_SEGMENT_64):
                    var command: segment_command_64 = extractor.extract(at: offset)!

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

    private func isEncrypted() -> Bool {
        let encLoadCommands: [EncryptionCommand] = loadCommands.filter { $0 is EncryptionCommand }.map { $0 as! EncryptionCommand }

        for elc: EncryptionCommand in encLoadCommands {
            guard elc.command.cryptid != 1 else {
                return true
            }
        }

        return false
    }
}
