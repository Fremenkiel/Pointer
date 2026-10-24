#!/usr/bin/env swift
import Foundation

/// The place of one module in the layer graph of docs/architecture.md section 3.
struct LayerEntry {
    /// The layer number. A module can import only modules in the same or a lower layer.
    let layer: Int
    /// True for a feature package. Feature packages never import each other.
    let isFeature: Bool
}

/// One rule violation, printed in the format that Xcode shows as an error.
struct Finding {
    /// The file that holds the violation.
    let path: String
    /// The line of the violation, or 1 for a whole-file finding.
    let line: Int
    /// The rule ID of docs/code-of-code.md.
    let rule: String
    /// The message that names the fault and the fix.
    let message: String

    /// The finding as one line of output.
    var text: String { "\(path):\(line): error: \(rule) \(message)" }
}

let layerTable: [String: LayerEntry] = [
    "Geometry": LayerEntry(layer: 0, isFeature: false),
    "Model": LayerEntry(layer: 0, isFeature: false),
    "InkEngine": LayerEntry(layer: 0, isFeature: false),
    "Persistence": LayerEntry(layer: 1, isFeature: false),
    "Rendering": LayerEntry(layer: 1, isFeature: false),
    "Export": LayerEntry(layer: 1, isFeature: false),
    "DesignSystem": LayerEntry(layer: 1, isFeature: false),
    "CanvasFeature": LayerEntry(layer: 2, isFeature: true),
    "WorkspaceFeature": LayerEntry(layer: 2, isFeature: true),
    "BackupFeature": LayerEntry(layer: 2, isFeature: true),
    "PointerApp": LayerEntry(layer: 3, isFeature: false),
]

/// Returns the reason why `importer` must not depend on `imported`, or nil if it can.
func violation(importer: String, imported: String) -> String? {
    guard importer != imported,
        let from = layerTable[importer],
        let to = layerTable[imported]
    else { return nil }
    if to.layer > from.layer {
        return "\(importer) (layer \(from.layer)) depends on \(imported) (layer \(to.layer)). "
            + "Move the shared code down to layer \(from.layer) or lower."
    }
    if from.isFeature && to.isFeature {
        return "Feature package \(importer) depends on feature package \(imported). "
            + "Move the shared code to a layer 1 package."
    }
    return nil
}

/// Reads the `--root <path>` argument. The default is the current folder.
func rootFolder() -> URL {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--root"), flag + 1 < arguments.count else {
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    return URL(fileURLWithPath: arguments[flag + 1])
}

/// Returns the package folders under `Packages/`, sorted by name.
func packageFolders(root: URL) -> [URL] {
    let packages = root.appendingPathComponent("Packages")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: packages.path)) ?? []
    return names.sorted()
        .map { packages.appendingPathComponent($0) }
        .filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Package.swift").path)
        }
}

/// Runs `swift package dump-package` in `folder` and returns the parsed manifest.
func dumpPackage(folder: URL) throws -> [String: Any] {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "package", "dump-package", "--package-path", folder.path]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
        let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        throw NSError(domain: "check-layers", code: Int(process.terminationStatus))
    }
    return manifest
}

/// Checks one declared dependency of package `name` (ARCH-02, BUILD-03).
///
/// A dependency must be a package of the layer table in the `packages` folder. A local path to
/// any other folder is third-party code, for example a vendored copy of a library.
func checkDependency(
    _ dependency: [String: Any],
    of name: String,
    path: String,
    packages: URL
) -> Finding? {
    guard let local = (dependency["fileSystem"] as? [[String: Any]])?.first,
        let localPath = local["path"] as? String
    else {
        let message =
            "\(name) has a remote dependency. "
            + "The app links no third-party code. Use a local path dependency."
        return Finding(path: path, line: 1, rule: "BUILD-03", message: message)
    }
    let folder = URL(fileURLWithPath: localPath).resolvingSymlinksInPath()
    let imported = folder.lastPathComponent
    guard layerTable[imported] != nil,
        folder.deletingLastPathComponent().path == packages.resolvingSymlinksInPath().path
    else {
        let message =
            "\(name) depends on \(localPath), which is not a Pointer package in Packages/. "
            + "The app links no third-party code."
        return Finding(path: path, line: 1, rule: "BUILD-03", message: message)
    }
    return violation(importer: name, imported: imported).map {
        Finding(path: path, line: 1, rule: "ARCH-02", message: $0)
    }
}

/// Fails on each binary target of a manifest, because a binary is third-party code (BUILD-03).
func checkBinaryTargets(manifest: [String: Any], of name: String, path: String) -> [Finding] {
    let targets = manifest["targets"] as? [[String: Any]] ?? []
    return targets.filter { $0["type"] as? String == "binary" }.map {
        let target = $0["name"] as? String ?? "?"
        let message =
            "\(name) has the binary target \(target). "
            + "The app links no third-party code. Write the code in a package."
        return Finding(path: path, line: 1, rule: "BUILD-03", message: message)
    }
}

/// Checks the declared dependencies of one package (ARCH-02, BUILD-03).
func checkManifest(folder: URL) -> [Finding] {
    let name = folder.lastPathComponent
    let path = folder.appendingPathComponent("Package.swift").path
    guard layerTable[name] != nil else {
        let message =
            "Unknown package \(name). Add it to the layer table "
            + "in Scripts/check-layers.swift and to docs/architecture.md."
        return [Finding(path: path, line: 1, rule: "ARCH-02", message: message)]
    }
    guard let manifest = try? dumpPackage(folder: folder) else {
        let message = "swift package dump-package failed for \(name). Fix the manifest."
        return [Finding(path: path, line: 1, rule: "ARCH-02", message: message)]
    }
    let packages = folder.deletingLastPathComponent()
    let dependencies = manifest["dependencies"] as? [[String: Any]] ?? []
    return checkBinaryTargets(manifest: manifest, of: name, path: path)
        + dependencies.compactMap {
            checkDependency($0, of: name, path: path, packages: packages)
        }
}

/// Returns the Swift files under `folder`, sorted by path.
func swiftFiles(in folder: URL) -> [URL] {
    guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    else {
        return []
    }
    return walker.compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" && !$0.path.contains("/.build/") }
        .sorted { $0.path < $1.path }
}

let importKinds = "typealias|struct|class|enum|protocol|let|var|func"
/// An access level before `import`, as Swift 6 allows (SE-0409).
let importAccess = "public|package|internal|fileprivate|private"
let importPattern = try NSRegularExpression(
    pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:"#
        + importAccess
        + #")\s+)?import\s+(?:(?:"#
        + importKinds
        + #")\s+)?(\w+)"#
)

/// Checks each `import` line of the Swift files of one module (ARCH-02).
func checkImports(module: String, folder: URL) -> [Finding] {
    var findings: [Finding] = []
    for file in swiftFiles(in: folder) {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
            findings.append(
                Finding(
                    path: file.path,
                    line: 1,
                    rule: "ARCH-02",
                    message: "The file is not UTF-8 text."
                )
            )
            continue
        }
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = importPattern.firstMatch(in: line, range: range),
                let nameRange = Range(match.range(at: 1), in: line),
                let reason = violation(importer: module, imported: String(line[nameRange]))
            else { continue }
            findings.append(
                Finding(path: file.path, line: index + 1, rule: "ARCH-02", message: reason)
            )
        }
    }
    return findings
}

let localReferencePattern = try NSRegularExpression(pattern: #"^\s*relativePath = "?([^";]+)"?;"#)

/// Returns the third-party reference on one line of the Xcode project, or nil if it has none.
func projectProblem(line: String) -> String? {
    if line.contains("isa = XCRemoteSwiftPackageReference;") {
        return "The project has a remote package."
    }
    if line.contains("\tpath = ") && line.contains(".xcframework") {
        return "The project references a prebuilt framework."
    }
    let range = NSRange(line.startIndex..., in: line)
    guard let match = localReferencePattern.firstMatch(in: line, range: range),
        let pathRange = Range(match.range(at: 1), in: line)
    else { return nil }
    let reference = String(line[pathRange])
    let name = URL(fileURLWithPath: reference).lastPathComponent
    guard reference != "Packages/\(name)" || layerTable[name] == nil else { return nil }
    return "The project references the package \(reference), which is not in Packages/."
}

/// Fails on third-party code in the Xcode project (BUILD-03).
///
/// The project can reference only the packages of the layer table in `Packages/`. A remote
/// package, a local package in another folder, or a prebuilt framework fails.
func checkProject(root: URL) -> [Finding] {
    let project = root.appendingPathComponent("Pointer.xcodeproj/project.pbxproj")
    guard let text = try? String(contentsOf: project, encoding: .utf8) else { return [] }
    return text.components(separatedBy: "\n").enumerated().compactMap { index, line in
        projectProblem(line: line).map {
            Finding(
                path: project.path,
                line: index + 1,
                rule: "BUILD-03",
                message: $0 + " The app links no third-party code."
            )
        }
    }
}

let root = rootFolder()
let folders = packageFolders(root: root)
var findings = checkProject(root: root)
for folder in folders {
    findings += checkManifest(folder: folder)
    findings += checkImports(
        module: folder.lastPathComponent,
        folder: folder.appendingPathComponent("Sources")
    )
}
findings += checkImports(module: "PointerApp", folder: root.appendingPathComponent("PointerApp"))
for finding in findings {
    print(finding.text)
}
print("check-layers: \(folders.count) packages, \(findings.count) findings")
exit(findings.isEmpty ? 0 : 1)
