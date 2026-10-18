import Combine
import Foundation

/// Each line below breaks one rule.
public struct Violations {
    /// A force unwrap, a force try, a force cast, and an implicitly unwrapped optional.
    func safety(_ value: Int?, _ any: Any) throws -> Int {
        let unwrapped = value!
        let decoded = try! JSONSerialization.jsonObject(with: Data())
        let cast = any as! Int
        var implicit: Int!
        implicit = unwrapped
        _ = decoded
        return cast + implicit
    }

    /// Jumps that FLOW-02 and FLOW-03 ban.
    func flow(_ value: Int) -> Int {
        outer: for item in 0..<value {
            for inner in 0..<item {
                _ = inner
                if inner > 2 { break outer }
            }
        }
        while true {
            return value
        }
    }

    /// FLOW-02 bans fallthrough.
    func fall(_ value: Int) -> Int {
        switch value {
        case 0:
            _ = value
            fallthrough
        default:
            return 1
        }
    }

    /// Logging, fatalError, conditional compilation, and a to-do note without an issue.
    func misc() {
        print("text")
        // TODO: no issue number
        #if os(iOS)
            fatalError("stop")
        #endif
    }

    /// Unsafe types and unsafe attributes.
    func unsafe(_ pointer: UnsafeRawPointer) -> Int {
        nonisolated(unsafe) var count = 0
        count += 1
        return count
    }

    /// Singletons, the file system, and the database outside their packages.
    func singletons() -> String {
        let path = FileManager.default.currentDirectoryPath
        return path + Bundle.main.bundlePath + ProcessInfo.processInfo.hostName
    }

    /// SAFE-10: SQL text built from a value.
    func sql(_ title: String) -> Int32 {
        sqlite3_exec(nil, "DELETE FROM workspace WHERE title = '\(title)'", nil, nil, nil)
    }
}

/// SCOPE-02: the class is not final.
public class Open {}
