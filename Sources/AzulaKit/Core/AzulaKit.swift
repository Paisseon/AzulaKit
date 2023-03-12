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
        dylibs: [String],
        remove: [String],
        targetURL url: URL,
        printer: (any PrettyPrinter)? = nil
    ) {
        // Initialise all the variables

        payloads = dylibs
        removed = remove
        pretty = printer
        targetURL = url
        target = (try? .init(contentsOf: url)) ?? Data()
        extractor = Extractor(pretty: pretty, target: target)
        patcher = Patcher(pretty: pretty, targetURL: url)
        injector = Injector(extractor: extractor, patcher: patcher, pretty: pretty)
        remover = Remover(extractor: extractor, patcher: patcher, pretty: pretty)

        // Parse the target binary to get headers and load commands

        guard let fatHeader: fat_header = extractor.extract() else {
            return
        }

        if [FAT_CIGAM, FAT_CIGAM_64, FAT_MAGIC, FAT_MAGIC_64].contains(fatHeader.magic) {
            let archCount: UInt32 = _OSSwapInt32(fatHeader.nfat_arch)
            var offset: Int = MemoryLayout<fat_header>.size - MemoryLayout<fat_arch>.size
            
            pretty?.print(Log(text: "Target has \(archCount) arches", type: .info))
            
            for _ in 0 ..< archCount {
                offset += MemoryLayout<fat_arch>.size
                
                if let arch: fat_arch = extractor.extract(at: offset) {
                    let archOffset: Int = .init(_OSSwapInt32(arch.offset))
                    let header: mach_header_64 = extractor.extract(at: archOffset)!
                    let mh: MachHeader = .init(header: header, offset: archOffset)
                    let isByteSwapped: Bool = [MH_CIGAM, MH_CIGAM_64].contains(header.magic)
                    
                    machHeaders.append(mh)
                    loadCommands.append(contentsOf: getLoadCommands(for: mh, isByteSwapped: isByteSwapped))
                }
            }
        } else {
            pretty?.print(Log(text: "Target has 1 arch", type: .info))
            
            if let header: mach_header_64 = extractor.extract() {
                let mh: MachHeader = .init(header: header, offset: 0)
                let isByteSwapped: Bool = [MH_CIGAM, MH_CIGAM_64].contains(header.magic)
                
                machHeaders = [mh]
                loadCommands = getLoadCommands(for: mh, isByteSwapped: isByteSwapped)
            }
        }
    }

    // MARK: Public

    @discardableResult
    public func inject() -> Bool {
        guard !isEncrypted() else {
            pretty?.print(Log(text: "Binary is encrypted, you must decrypt", type: .error))
            return false
        }
        
        for (payload, mh): (String, MachHeader) in product(payloads, machHeaders) {
            pretty?.print(Log(text: "Current arch is \(getArchName(for: mh.header))", type: .info))

            guard injector.inject(payload, mh: mh, isByteSwapped: [MH_CIGAM, MH_CIGAM_64].contains(mh.header.magic)) else {
                return false
            }
            
            pretty?.print(Log(text: "Injected \(payload.components(separatedBy: "/").last ?? "???")", type: .info))
        }

        return true
    }

    @discardableResult
    public func remove() -> Bool {
        remover.remove(removed)
    }
    
    // Thanks to paradiseduo

    @discardableResult
    public func slice() -> Bool {
        let signatureLoadCommands: [SignatureCommand] = loadCommands.lazy.compactMap { $0 as? SignatureCommand }
        var patches: [Patch] = []
        var strip: Int = 0x0000_1337

        for cslc: SignatureCommand in signatureLoadCommands {
            patches.append(Patch(offset: cslc.offset, data: Data(bytes: &strip, count: 4)))
        }

        return patcher.patch(patches)
    }

    // MARK: Private

    private let extractor: Extractor
    private let injector: Injector
    private let patcher: Patcher
    private let payloads: [String]
    private let pretty: (any PrettyPrinter)?
    private let removed: [String]
    private let remover: Remover
    private let target: Data
    private let targetURL: URL
    
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
        var offset: Int = mh.offset + MemoryLayout.size(ofValue: mh.header)
        var ret: [any LoadCommand] = []

        for _ in 0 ..< mh.header.ncmds {
            guard let loadCommand: load_command = extractor.extract(at: offset) else {
                pretty?.print(Log(text: String(format: "Load command at 0x%X is out-of-bounds", offset), type: .error))
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
                    offset += Int(loadCommand.cmdsize)
                    continue
            }

            ret.append(myLoadCommand)
            offset += Int(loadCommand.cmdsize)
        }

        return ret
    }

    private func isEncrypted() -> Bool {
        let encLoadCommands: [EncryptionCommand] = loadCommands.lazy.compactMap { $0 as? EncryptionCommand }

        for elc: EncryptionCommand in encLoadCommands {
            guard elc.command.cryptid == 0 else {
                return true
            }
        }

        return false
    }
    
    // "Can I have Algorithms to use product() in my code?"
    // "No, we have product() at home"
    //
    // product() at home:
    
    private func product<T, U>(
        _ a: [T],
        _ b: [U]
    ) -> [(T, U)] {
        var result: [(T, U)] = []
        
        for i in a {
            for j in b {
                result.append((i, j))
            }
        }
        
        return result
    }
}
