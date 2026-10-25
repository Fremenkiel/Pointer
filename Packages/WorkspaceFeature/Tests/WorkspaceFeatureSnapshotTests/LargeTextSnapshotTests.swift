import Model
import SwiftUI
import Testing

@testable import WorkspaceFeature

/// The selector at the largest text size, AX5 (D-179, TEST-07). The list grows and wraps its
/// rows. The workspace button keeps its size and shows the Large Content Viewer.
@MainActor
@Suite("Selector snapshots at the largest text size")
struct LargeTextSnapshotTests {
    @Test("The list grows up to its widest size, and a long name takes 2 lines")
    func list() throws {
        var workspaces = try WorkspaceSelectorSnapshotTests.three()
        let last = workspaces[2]
        workspaces[2] = try Workspace(
            id: last.id,
            meta: last.meta,
            title: "Graph traversal and shortest paths",
            sortKey: last.sortKey
        )
        try ViewSnapshot.assertMatches(
            WorkspaceSelectorSnapshotTests.list(
                workspaces,
                current: workspaces[1].id,
                canCreate: true
            )
            .environment(\.dynamicTypeSize, .accessibility5),
            named: "workspace-list-ax5"
        )
    }

    @Test("The workspace button keeps the size of the standard text size")
    func button() throws {
        try ViewSnapshot.assertMatches(
            WorkspaceButton(title: "Data structures") {}
                .environment(\.dynamicTypeSize, .accessibility5),
            named: "workspace-button"
        )
    }
}
