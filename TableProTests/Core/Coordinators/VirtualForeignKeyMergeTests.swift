//
//  VirtualForeignKeyMergeTests.swift
//  TableProTests
//

import Foundation
@testable import TablePro
import Testing

struct VirtualForeignKeyMergeTests {
    private func virtualKey(
        column: String = "artist_id",
        referencedTable: String = "artists",
        referencedColumn: String = "id"
    ) -> VirtualForeignKey {
        VirtualForeignKey(column: column, referencedTable: referencedTable, referencedColumn: referencedColumn)
    }

    @Test("Real and virtual keys on different columns coexist")
    func differentColumnsCoexist() {
        let real = ["user_id": TestFixtures.makeForeignKeyInfo()]
        let merged = VirtualForeignKeyMerge.merged(real: real, virtual: [virtualKey()])

        #expect(merged.count == 2)
        #expect(merged["user_id"]?.isVirtual == false)
        #expect(merged["artist_id"]?.referencedTable == "artists")
        #expect(merged["artist_id"]?.isVirtual == true)
    }

    @Test("A real key wins the column it shares with a virtual one")
    func realWinsConflict() {
        let real = ["user_id": TestFixtures.makeForeignKeyInfo(referencedTable: "accounts")]
        let virtualKeys = [virtualKey(column: "user_id", referencedTable: "users")]
        let merged = VirtualForeignKeyMerge.merged(real: real, virtual: virtualKeys)

        #expect(merged.count == 1)
        #expect(merged["user_id"]?.referencedTable == "accounts")
        #expect(merged["user_id"]?.isVirtual == false)
    }

    @Test("Virtual keys stay marked virtual in the merged dictionary")
    func virtualMarkerSurvives() {
        let merged = VirtualForeignKeyMerge.merged(real: [:], virtual: [virtualKey()])

        #expect(merged["artist_id"]?.isVirtual == true)
        #expect(merged["artist_id"]?.name == "virtual_artist_id_artists")
    }

    @Test("Empty virtual configuration returns the real dictionary unchanged")
    func emptyVirtualReturnsOriginal() {
        let real = ["user_id": TestFixtures.makeForeignKeyInfo()]

        #expect(VirtualForeignKeyMerge.merged(real: real, virtual: []) == real)
        #expect(VirtualForeignKeyMerge.merged(real: [:], virtual: []).isEmpty)
    }

    @Test("Virtual keys alone populate a table with no real constraints")
    func virtualOnlyPopulates() {
        let virtualKeys = [
            virtualKey(),
            virtualKey(column: "genre_id", referencedTable: "genres")
        ]
        let merged = VirtualForeignKeyMerge.merged(real: [:], virtual: virtualKeys)

        #expect(merged.count == 2)
        #expect(merged.values.allSatisfy { $0.isVirtual })
    }

    @Test("Container qualifiers survive the merge")
    func containerQualifiersSurvive() {
        let qualified = VirtualForeignKey(
            column: "order_id",
            referencedTable: "orders",
            referencedColumn: "id",
            referencedDatabase: "sales",
            referencedSchema: "archive"
        )
        let merged = VirtualForeignKeyMerge.merged(real: [:], virtual: [qualified])

        #expect(merged["order_id"]?.referencedDatabase == "sales")
        #expect(merged["order_id"]?.referencedSchema == "archive")
    }

    @Test("The first of two virtual keys on one column wins")
    func duplicateVirtualColumnsKeepFirst() {
        let virtualKeys = [
            virtualKey(column: "ref_id", referencedTable: "first"),
            virtualKey(column: "ref_id", referencedTable: "second")
        ]
        let merged = VirtualForeignKeyMerge.merged(real: [:], virtual: virtualKeys)

        #expect(merged.count == 1)
        #expect(merged["ref_id"]?.referencedTable == "first")
    }
}
