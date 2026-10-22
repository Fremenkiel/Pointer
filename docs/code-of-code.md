# Code of Code

This document is the coding standard of Pointer. Every contributor must obey it, people and AI agents alike. A pull request that breaks a rule is not merged.

The standard combines four sources:

1. The NASA/JPL "Power of 10" rules for safety-critical code (Holzmann, 2006).
2. The rules of the best-structured Swiss open-source iOS codebases: Proton, Threema, and Infomaniak.
3. Apple's Swift API Design Guidelines and the Google and Airbnb Swift style guides.
4. Design by Contract (Bertrand Meyer, ETH Zurich): each function states and enforces what it needs and what it gives.

## 0. How to read this document

- Each rule has an ID, for example `SAFE-03`. Code review comments and commit messages refer to the ID.
- "Must" and "must not" are mandatory. "Can" is an option.
- Each rule has an enforcement method: compiler, lint, CI script, test, or review.
- Rules apply in three tiers, after the JPL "levels of compliance" idea:

| Tier | Packages | Rules |
|---|---|---|
| A (core) | `Geometry`, `Model`, `InkEngine`, `Persistence` | All rules. |
| B (engine) | `Rendering`, `Export` | All rules. `SAFE-09` allows Metal buffer pointers in files named `*+Unsafe.swift`. |
| C (interface) | `CanvasFeature`, `WorkspaceFeature`, `BackupFeature`, `DesignSystem`, `PointerApp` | All rules except `CONTRACT-02` (assertion density). |

One exception applies in Tier A: `Persistence` can use SQLite C pointers in files named `SQLite*+Unsafe.swift` (`SAFE-09`).

## 1. Sources and what each one gives

| Source | What we take |
|---|---|
| NASA/JPL Power of 10 | Simple control flow, bounded loops, short functions, assertions, small scope, checked results, no unsafe pointers, zero warnings. |
| Proton (ProtonVPN iOS, Proton Authenticator) | Layered local packages: foundations, shared, features. Features never import features. Domain types are plain value types. Strict lint in CI. No `print`. |
| Threema (threema-ios) | One lint rule protects one architecture rule. The lint message tells you what to do instead. Formatting belongs to the formatter, not to the linter. |
| Infomaniak (ios-kMail, ios-kDrive) | An `AGENTS.md` with a context map, a pull request checklist, and a self-correction rule. Design tokens instead of raw values. Swift Testing for new tests. A schema change needs a migration. Conventional Commits. |
| SBB (mobile-ios-design-swiftui) | Every UI component has a snapshot test. |
| Apple, Google, Airbnb style guides | Naming, documentation comments, access control, `final` classes, no force unwrap. |
| Meyer, Design by Contract | Preconditions, postconditions, and invariants as code. |

Sources: <https://en.wikipedia.org/wiki/The_Power_of_10:_Rules_for_Developing_Safety-Critical_Code>, <https://github.com/ProtonVPN/ios-mac-app>, <https://github.com/protonpass/ios-authenticator>, <https://github.com/threema-ch/threema-ios>, <https://github.com/Infomaniak/ios-kMail/blob/master/AGENTS.md>, <https://github.com/SchweizerischeBundesbahnen/mobile-ios-design-swiftui>, <https://www.swift.org/documentation/api-design-guidelines/>, <https://google.github.io/swift/>, <https://github.com/airbnb/swift>.

## 2. Power of 10, mapped to Swift

| P10 | Original rule (short form) | Pointer rule |
|---|---|---|
| 1 | Simple control flow. No `goto`, no recursion. | `FLOW-01`, `FLOW-02` |
| 2 | Each loop has a fixed upper bound. | `FLOW-03` |
| 3 | No dynamic memory allocation after initialization. | `PERF-01`, `PERF-02` |
| 4 | A function fits on one sheet of paper (about 60 lines). | `SIZE-01` |
| 5 | At least two assertions per function, without side effects, with a recovery action. | `CONTRACT-01` to `CONTRACT-04` |
| 6 | Declare data at the smallest possible scope. | `SCOPE-01` to `SCOPE-04` |
| 7 | Check every return value. Check every parameter. | `SAFE-01` to `SAFE-05` |
| 8 | Limit the preprocessor. | `SAFE-08` |
| 9 | Limit pointers. No function pointers. | `SAFE-09` |
| 10 | Compile with all warnings from day one. Zero warnings. Daily static analysis. | `BUILD-01` to `BUILD-04` |

## 3. Rules

### 3.1 Build

- `BUILD-01` Every target and package uses the Swift 6 language mode with complete strict concurrency checking. Enforcement: compiler.
- `BUILD-02` Warnings are errors. Xcode targets set `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` and `GCC_TREAT_WARNINGS_AS_ERRORS = YES`. Packages set `.treatAllWarnings(as: .error)`. Enforcement: compiler.
- `BUILD-03` The app links no third-party code. A new framework dependency, even from Apple, needs an entry in `docs/decisions.md`. Development tools from third parties (linters, formatters, rule checkers) are allowed (decision D-04). They never link into the app. Enforcement: a CI script fails the build on a third-party package in the dependency graph of the app target.
- `BUILD-04` CI runs `xcodebuild analyze` on each pull request. Zero analyzer findings. Enforcement: CI.

### 3.2 Architecture

- `ARCH-01` Code lives in the package of its layer (see [architecture.md](architecture.md) section 3). The app target holds only composition and scene setup.
- `ARCH-02` A package imports only packages in its own layer or a lower layer. A feature package never imports another feature package. Enforcement: CI script `Scripts/check-layers.swift`.
- `ARCH-03` Tier A packages import only `Foundation`, `CryptoKit`, `os`, and other Tier A packages. `Persistence` also imports `SQLite3` (`ARCH-04`). They never import `UIKit`, `SwiftUI`, `Metal`, or `CoreGraphics`. Enforcement: lint.
- `ARCH-04` Only `Persistence` touches the database and the file system. Only `Rendering` touches Metal. Only `Export` makes PDFs. Enforcement: lint (Threema-style: the rule bans `import SQLite3`, `FileManager`, `MTLDevice`, and `UIGraphicsPDFRenderer` outside their own package).
- `ARCH-05` Dependencies come in through initializers. No singletons, no service locators, no global mutable state. Apple singletons (`UIApplication.shared`, `FileManager.default`) appear only in `PointerApp` and are passed down. Enforcement: lint and review.
- `ARCH-06` Model types are `struct` or `enum`, `Sendable`, and immutable where possible (`let` over `var`). One exception: `InkPoints` is a `final class` with `let` properties only, so that strokes share their points (see [data-model.md](data-model.md) section 7.4).
- `ARCH-07` No haptics and no sounds (PEN-06). Haptics that the system plays by itself are accepted (D-23). The code must not use `UICanvasFeedbackGenerator`, `UIFeedbackGenerator` or its subclasses, `CoreHaptics`, `AVAudioPlayer`, or `AudioServicesPlaySystemSound`. Enforcement: lint, severity error, no allowed path.

### 3.3 Control flow

- `FLOW-01` No recursion, with one exception: a function that walks the card tree. That function must take a `depth` parameter and must start with `precondition(depth <= Limits.maxDepth)`. An iterative walk with an explicit stack is preferred. Enforcement: review.
- `FLOW-02` No `fallthrough`. No labeled `break` or `continue`. Enforcement: lint.
- `FLOW-03` Each loop has a bound that a reader can see. A `for` loop over a collection is bounded by the collection, and the collection is bounded by a constant in `Limits`. A `while` or `repeat` loop must compare a counter against a named constant. An `AsyncSequence` loop must call `try Task.checkCancellation()` in its body. `while true` is not allowed. Enforcement: lint and review.
- `FLOW-04` Early exit with `guard`. Nesting depth is at most 3 levels inside a function body. Enforcement: lint.

### 3.4 Size

- `SIZE-01` A function body has at most 40 lines (warning) and 60 lines (error). Enforcement: lint.
- `SIZE-02` Cyclomatic complexity (the number of paths through a function) is at most 8 (warning) and 12 (error). Enforcement: lint.
- `SIZE-03` A type body has at most 250 lines. A file has at most 400 lines. Enforcement: lint.
- `SIZE-04` A function has at most 5 parameters. If it needs more, group them in a struct. Enforcement: lint.
- `SIZE-05` Line length is at most 100 characters. Enforcement: formatter.
- `SIZE-06` One main type per file. The file has the name of the type. An extension for one protocol conformance can go in `Type+Protocol.swift`.

### 3.5 Contracts

- `CONTRACT-01` Each function that is not private states its contract in its documentation comment: what it needs (`- Precondition:`), what it returns, and what it throws.
- `CONTRACT-02` Tier A and B functions with more than 5 lines have at least two contract checks on average per package. A contract check is a `precondition`, an `assert`, or a `guard` that throws or returns an error value. Enforcement: CI script `Scripts/assertion-density.swift` reports the average per package and fails below 2.0.
- `CONTRACT-03` Use the right check for the right fault:

| Fault | Check | Active in release builds |
|---|---|---|
| The caller broke the contract (a programmer error) | `precondition(_:_:)` | Yes |
| An internal invariant broke (a programmer error) | `assert(_:_:)` | No |
| Bad external data: a file, user input, or a system value | `guard ... else { throw ... }` | Yes |

- `CONTRACT-04` A check has no side effects. A failed check that does not stop the program leads to a defined recovery: a thrown error, a returned error value, or a skipped item with a log entry. Each message names the value that failed.

```swift
/// Splits a stroke where the eraser circle covers its points.
///
/// - Precondition: `radius` is greater than zero.
/// - Returns: The parts of the stroke outside the circle. Empty if the circle covers all points.
func split(_ stroke: Stroke, by center: Point, radius: Double) -> [StrokePart] {
    precondition(radius > 0, "Eraser radius must be positive, got \(radius)")
    precondition(stroke.points.count >= 2, "Stroke \(stroke.id) has fewer than 2 points")
    ...
}
```

### 3.6 Safety

- `SAFE-01` No force unwrap (`!`), no `try!`, no `as!`, no implicitly unwrapped optionals. This applies in tests too: use `try #require(...)`. Enforcement: lint, severity error.
- `SAFE-02` No `try?` that drops an error in silence. `try?` is allowed only with a handler for the `nil` case in the same statement or the next one. Enforcement: review.
- `SAFE-03` No `@discardableResult` without a documentation comment that gives the reason. Enforcement: lint.
- `SAFE-04` Errors are typed. Each package has one error enum. Functions use typed throws (`throws(PersistenceError)`) where the error set is known. Enforcement: review.
- `SAFE-05` Integer conversions from external data use `init(exactly:)` or a `guard` on the range. No unchecked `Int(someUInt64)` on file data or database data. Enforcement: review.
- `SAFE-10` SQL uses prepared statements with bound parameters. No SQL text built from values with string interpolation. Each SQLite result code is compared with the expected code, and a mismatch throws `PersistenceError` with `sqlite3_errmsg`. Enforcement: lint bans `sqlite3_exec` with an interpolated string, and review.
- `SAFE-06` No `print`, `debugPrint`, `NSLog`, or `dump`. Use `os.Logger` with a subsystem and a category per package. Never log text or ink content of the user. Enforcement: lint.
- `SAFE-07` No `fatalError` except in `init(coder:)` stubs that UIKit requires. Use `preconditionFailure` with a message for unreachable code. Enforcement: lint.
- `SAFE-08` `#if` only for `DEBUG`, `targetEnvironment(simulator)`, and `canImport`. No feature flags with `#if`. Enforcement: lint.
- `SAFE-09` No `Unsafe*Pointer`, `unsafeBitCast`, `Unmanaged`, `nonisolated(unsafe)`, `@unchecked Sendable`, or `@preconcurrency`. Exceptions: Tier B files with the suffix `+Unsafe.swift`, and the SQLite wrapper files `Packages/Persistence/**/SQLite*+Unsafe.swift`. Each use there has a comment that states why it is safe. No unsafe type leaves these files: their public API uses `Data`, `String`, and Swift numbers only. Enforcement: lint that excludes those files.

### 3.7 Scope

- `SCOPE-01` Access control is as strict as possible. The default is `private`. Use `internal` only for a declaration that another file in the package uses. Use `public` only for a declaration that another package uses. Enforcement: review, and Periphery-style dead code checks in CI.
- `SCOPE-02` Classes are `final` unless a subclass exists. Enforcement: lint.
- `SCOPE-03` `let` before `var`. A `var` that never changes is an error. Enforcement: compiler.
- `SCOPE-04` SwiftUI property wrappers (`@State`, `@Environment`, `@Binding` storage) are `private`. Enforcement: lint (Infomaniak rule).

### 3.8 Performance

- `PERF-01` No allocation in Pointer code in the per-frame path and the per-sample path. This covers `touchesMoved`, the frame callback, and the shaders. Buffers use `reserveCapacity` once and are reused. No closures that capture in these paths. The allocations inside Metal do not count (D-43). Enforcement: an allocation test that subtracts the count of a bare Metal frame with the same passes, and allocation tests in Instruments for each milestone.
- `PERF-02` No disk access and no `Task` creation on the main actor in the per-frame path. Enforcement: review and signposts.
- `PERF-03` Each hot path has an `OSSignposter` interval and a performance test with a baseline (see [architecture.md](architecture.md) section 12). Enforcement: CI on a device.

### 3.9 Naming and style

- `STYLE-01` Follow the Swift API Design Guidelines. Clarity at the point of use comes first. Boolean names read as statements (`isDeleted`, `hasPreview`). Protocols that describe what a thing is are nouns (`LibraryRepository`). Protocols that describe a capability end in `-able` or `-ing`.
- `STYLE-02` No abbreviations except standard ones: `id`, `url`, `pdf`, `hlc`, `gpu`. Acronyms keep one case: `pdfData`, `PDFExporter`.
- `STYLE-03` No raw values in UI code. Colors, spacing, sizes, durations, and icons come from `DesignSystem`. Numbers in logic come from `Limits` or a named `static let`. Enforcement: lint bans number literals in `.padding`, `.frame`, `Color(`, and `UIColor(`.
- `STYLE-04` `swift format` (part of the Xcode toolchain) owns the format. The configuration is `.swift-format` in the repository root. A formatting question in review is answered by the tool, not by a person.
- `STYLE-05` No user-facing string literals. User-facing text comes from a String Catalog (`Localizable.xcstrings`) through `String(localized:)`.

### 3.10 Comments and documentation

- `DOC-01` Each declaration that is not `private` has a documentation comment (`///`). The first line is one sentence that says what it does. Enforcement: `swift format lint` rule `AllPublicDeclarationsHaveDocumentation` for `public` and review for `internal`.
- `DOC-02` A comment in a function body says why, not what. If a comment says what the code does, rename or split the code instead.
- `DOC-03` Each number from research has a comment with the source. Example: `// 8 ms prediction limit: Cattan et al., ITS 2015. See docs/research.md 3.3.`
- `DOC-04` No commented-out code. No `TODO` without an issue reference: `// TODO(#42): ...`. Enforcement: lint.
- `DOC-05` No file header comments. Git holds the author and the date (Threema rule).
- `DOC-06` A change to a behavior in `docs/` updates the document in the same pull request.

### 3.11 Tests

- `TEST-01` New unit tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`). XCTest is only for UI tests and performance tests.
- `TEST-02` Each Tier A function that is not private has at least one test. Line coverage for each Tier A package is at least 90%. For Tier B it is at least 70%. Enforcement: CI reads the coverage report.
- `TEST-03` Each bug fix comes with a test that fails before the fix.
- `TEST-04` Tests are independent and can run in parallel. No shared mutable state. No real clock: inject a clock. No real file system in unit tests: use a temporary folder per test.
- `TEST-05` Test names are sentences that state the behavior: `@Test("Erasing the middle of a stroke leaves two parts")`.
- `TEST-06` Use parameterized tests (`@Test(arguments:)`) for limits and edges: zero, one, the limit, and the limit plus one.
- `TEST-07` Each UI component and each renderer output has a snapshot test. The test renders to an image with `UIGraphicsImageRenderer` or an offscreen Metal texture. It compares the image with a reference PNG in the repository, with a tolerance of 0.5% of the pixels. No snapshot library.
- `TEST-08` Each schema version has a fixture database and a migration test (see [data-model.md](data-model.md) section 12).
- `TEST-09` Each command has a test that applies it, reverts it, and compares the result with the start state. The comparison covers the live content (D-67).

Test pyramid: most tests are unit tests in Tier A. Fewer tests cover Tier B with snapshots. A few UI tests cover the main flows: create a workspace, draw, open a card, leave a card, undo, export.

### 3.12 Version control

- `GIT-01` Commit messages follow Conventional Commits: `feat(canvas): ...`, `fix(persistence): ...`, `test(ink): ...`, `docs: ...`, `refactor(...)`, `perf(...)`, `chore(...)`.
- `GIT-02` One logical change per commit. A commit builds and passes the tests.
- `GIT-03` A pull request names the requirement IDs and the rule IDs that it touches.
- `GIT-04` A change to a stored format increments the schema version and adds a migration and a fixture in the same pull request (Infomaniak rule).

## 4. Tools

Third-party development tools are allowed (decision D-04). They run in development and CI only, and the app never links them. SwiftLint owns the pattern rules and the size metrics, so the repository needs fewer scripts.

| Tool | Purpose | Source |
|---|---|---|
| Swift compiler | `BUILD-01`, `BUILD-02`, `SCOPE-03` | Xcode |
| `swift format` and `swift format lint` | Format and basic lint (`SAFE-01`, `DOC-01`) | Xcode toolchain |
| `xcodebuild analyze` | `BUILD-04` | Xcode |
| SwiftLint | Built-in rules and `custom_rules`: one rule per invariant, with an allowed path and a message that names the fix | Third party (D-04) |
| `Scripts/check-layers.swift` | `ARCH-02` | This repository |
| `Scripts/assertion-density.swift` | `CONTRACT-02` | This repository |
| SwiftLint metric rules | `SIZE-01` to `SIZE-04` (`function_body_length`, `cyclomatic_complexity`, `type_body_length`, `file_length`, `function_parameter_count`) | Third party (D-04) |

Each custom rule in `.swiftlint.yml` has this form (Threema pattern):

```yaml
custom_rules:
  arch_04_sqlite:
    name: "ARCH-04"
    regex: '\bimport SQLite3\b'
    excluded: "Packages/Persistence/"
    match_kinds: [keyword, identifier]
    message: "Only Persistence touches the database. Add a method to LibraryRepository instead."
    severity: error
```

The `match_kinds` key makes the rule skip comments and string literals.

A starting `.swift-format` configuration (make sure that the rule names match the output of `swift format dump-configuration` before the first commit):

```json
{
  "version": 1,
  "lineLength": 100,
  "indentation": { "spaces": 4 },
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeEachArgument": true,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": true,
    "NeverForceUnwrap": true,
    "NeverUseForceTry": true,
    "NeverUseImplicitlyUnwrappedOptionals": true,
    "NoLeadingUnderscores": true,
    "OrderedImports": true,
    "UseLetInEveryBoundCaseVariable": true,
    "ValidateDocumentationComments": true
  }
}
```

## 5. Pull request checklist

A pull request is ready only with each item true:

1. The build has zero warnings and zero analyzer findings.
2. `swift format lint`, `swiftlint --strict`, `Scripts/check-layers.swift`, and `Scripts/assertion-density.swift` pass.
3. All tests pass. Coverage meets `TEST-02`: `make coverage` passes (D-120).
4. New behavior has tests. A bug fix has a regression test.
5. Each new function that is not private has a documentation comment with its contract.
6. No new number literal outside `Limits`, `DesignSystem`, or a named constant with a source comment.
7. A stored format change has a schema increment, a migration, and a fixture.
8. The documents in `docs/` match the code.
9. The pull request names its requirement IDs and rule IDs.
10. Performance tests on the device show no regression over 10% (for changes in `InkEngine`, `Rendering`, or `CanvasFeature`).

## 6. Rules for AI agents

These rules add to all rules above. They apply to each agent that writes code in this repository.

- `AGENT-01` Read `AGENTS.md`, this document, and the document for the area you change before you write code.
- `AGENT-02` Do the smallest change that meets the task. Do not refactor code outside the task. Do not add features that the product specification does not list.
- `AGENT-03` Do not add a dependency to the app. Do not add a development tool without an entry in `docs/decisions.md`. Do not change a rule in this document. If a rule blocks the task, stop and ask the product owner.
- `AGENT-04` Stop and ask about a document that is unclear or that contradicts the code. Do not guess. Record the question in `docs/decisions.md`.
- `AGENT-05` Run the full checklist in section 5 before you report the task as done. Report each failure with its output.
- `AGENT-06` Record each correction from the product owner as a rule in the "Learned rules" section of `AGENTS.md`. Do this in the same pull request (Infomaniak self-correction pattern).
- `AGENT-07` Add each new folder to the context map of `AGENTS.md`.
