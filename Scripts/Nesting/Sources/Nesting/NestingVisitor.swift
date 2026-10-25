import SwiftSyntax

/// The deepest nesting of control flow in one function body (FLOW-04).
struct FunctionDepth {
    /// The line of the declaration.
    let line: Int
    /// The name of the function, an initializer, or an accessor.
    let name: String
    /// The most levels of control flow inside the body.
    let depth: Int
    /// The line of the deepest block.
    let deepestLine: Int
}

/// Counts the levels of control flow in each function body of one file (D-175).
///
/// The body of `if`, `else`, `guard`, `for`, `while`, `repeat`, `do`, `catch`, a `case` of a
/// `switch`, and a closure each add one level. An `else if` stays at the level of its `if`,
/// because its body hangs from the inner `if`. A `switch` adds its one level through its cases.
/// A nested function starts again at level 0.
final class NestingVisitor: SyntaxVisitor {
    /// The functions of the file, in the order of their ends.
    private(set) var functions: [FunctionDepth] = []
    private let converter: SourceLocationConverter
    /// One function whose body the visitor is in.
    private struct OpenFunction {
        let line: Int
        let name: String
        var depth = 0
        var deepest = 0
        var deepestLine: Int
    }

    /// The open functions, the innermost last.
    private var open: [OpenFunction] = []

    /// Makes a visitor for the file that `converter` reads.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    private func line(of node: some SyntaxProtocol) -> Int {
        node.startLocation(converter: converter).line
    }

    private func begin(_ node: some SyntaxProtocol, name: String) {
        open.append(OpenFunction(line: line(of: node), name: name, deepestLine: line(of: node)))
    }

    private func end() {
        guard let last = open.popLast() else { return }
        functions.append(
            FunctionDepth(
                line: last.line,
                name: last.name,
                depth: last.deepest,
                deepestLine: last.deepestLine
            )
        )
    }

    private func enter(_ node: some SyntaxProtocol) {
        guard let index = open.indices.last else { return }
        open[index].depth += 1
        if open[index].depth > open[index].deepest {
            open[index].deepest = open[index].depth
            open[index].deepestLine = line(of: node)
        }
    }

    private func leave() {
        guard let index = open.indices.last else { return }
        open[index].depth -= 1
    }

    /// `true` if `block` is the body of a construct that adds a level.
    private func addsLevel(_ block: CodeBlockSyntax) -> Bool {
        guard let parent = block.parent else { return false }
        return parent.is(IfExprSyntax.self) || parent.is(GuardStmtSyntax.self)
            || parent.is(ForStmtSyntax.self) || parent.is(WhileStmtSyntax.self)
            || parent.is(RepeatStmtSyntax.self) || parent.is(DoStmtSyntax.self)
            || parent.is(CatchClauseSyntax.self)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        begin(node, name: node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) { end() }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        begin(node, name: "init")
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) { end() }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        begin(node, name: "deinit")
        return .visitChildren
    }

    override func visitPost(_ node: DeinitializerDeclSyntax) { end() }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        // A computed property without `get` holds its statements in the accessor block.
        if node.accessors.is(CodeBlockItemListSyntax.self) { begin(node, name: "get") }
        return .visitChildren
    }

    override func visitPost(_ node: AccessorBlockSyntax) {
        if node.accessors.is(CodeBlockItemListSyntax.self) { end() }
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        begin(node, name: node.accessorSpecifier.text)
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) { end() }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        if addsLevel(node) { enter(node) }
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockSyntax) {
        if addsLevel(node) { leave() }
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        enter(node)
        return .visitChildren
    }

    override func visitPost(_ node: SwitchCaseSyntax) { leave() }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        enter(node)
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) { leave() }
}
