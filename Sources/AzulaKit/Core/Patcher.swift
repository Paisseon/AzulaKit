//
//  File.swift
//
//
//  Created by Lilliana on 06/03/2023.
//

import Foundation

struct Patcher {
    let targetURL: URL
    let pretty: (any PrettyPrinter)?

    func patch(
        _ patches: [Patch]
    ) -> Bool {
        guard !patches.isEmpty else {
            pretty?.print(Log(text: "No patches", type: .warn))
            return true
        }

        guard let handle: FileHandle = try? .init(forWritingTo: targetURL) else {
            pretty?.print(Log(text: "Couldn't get write handle to target", type: .error))
            return false
        }

        do {
            pretty?.print(Log(text: "Patching target...", type: .info))

            for patch in patches {
                if let offset: Int = patch.offset {
                    try handle.seek(toOffset: UInt64(offset))
                }

                try handle.write(contentsOf: patch.data)
            }

            try handle.close()
        } catch {
            pretty?.print(Log(text: error.localizedDescription, type: .error))
            return false
        }

        return true
    }
}
