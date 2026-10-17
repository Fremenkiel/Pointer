import Foundation
import Model
import SQLite3
import os

/// Tier A imports that ARCH-03 allows.
public struct Store {
    /// The current folder. Only Persistence touches the file system.
    func folder(manager: FileManager) -> String {
        #if DEBUG
            let name = manager.currentDirectoryPath
        #elseif targetEnvironment(simulator)
            let name = "simulator"
        #else
            let name = ""
        #endif
        return name
    }
}
