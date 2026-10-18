import Foundation
import Model
import SwiftUI
import Testing

@testable import WorkspaceFeature

@MainActor
@Suite(
    "Workspace selector snapshots",
    .enabled(
        if: ViewSnapshot.canReadReferences,
        "The references are on the Mac, so only the simulator reads them"
    )
)
struct WorkspaceSelectorSnapshotTests {
    @Test("The button shows the name of the current workspace")
    func button() throws {
        try ViewSnapshot.assertMatches(
            WorkspaceButton(title: "Data structures") {},
            named: "workspace-button"
        )
    }

    @Test("A long name ends with an ellipsis in the button")
    func longName() throws {
        let title = String(repeating: "Graph traversal ", count: 8)
        try ViewSnapshot.assertMatches(
            WorkspaceButton(title: title) {},
            named: "workspace-button-long"
        )
    }

    @Test("The list marks the current workspace and offers a new one")
    func list() throws {
        let workspaces = try Self.three()
        try ViewSnapshot.assertMatches(
            Self.list(workspaces, current: workspaces[1].id, canCreate: true),
            named: "workspace-list"
        )
    }

    @Test("At the limit, the list disables a new workspace and says why")
    func listAtLimit() throws {
        let workspaces = try Self.three()
        try ViewSnapshot.assertMatches(
            Self.list(workspaces, current: workspaces[0].id, canCreate: false),
            named: "workspace-list-limit"
        )
    }

    /// Three workspaces with fixed IDs and clock values.
    static func three() throws -> [Workspace] {
        let device = DeviceID(
            rawValue: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
        let meta = RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: device))
        let titles = ["Alpha", "Data structures", "Gamma"]
        let keys = ["V", "W", "X"]
        return try (0..<titles.count).map { index in
            let byte = UInt8(index + 1)
            let title = titles[index]
            let key = keys[index]
            return
                try Workspace(
                    id: WorkspaceID(
                        rawValue: UUID(uuid: (5, byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                    ),
                    meta: meta,
                    title: title,
                    sortKey: FractionalIndex(rawValue: key)
                )
        }
    }

    static func list(
        _ workspaces: [Workspace],
        current: WorkspaceID,
        canCreate: Bool
    ) -> some View {
        WorkspaceList(
            workspaces: workspaces,
            currentID: current,
            canCreate: canCreate,
            onSelect: { _ in },
            onCreate: {},
            onRename: { _ in },
            onDelete: { _ in }
        )
    }
}
