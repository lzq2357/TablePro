import Foundation
import Testing

@testable import TablePro

struct VirtualForeignKeyTransferTests {
    private func scope(
        connectionId: UUID,
        database: String? = "chinook",
        schema: String? = nil,
        table: String = "Album"
    ) -> TableScope {
        TableScope(connectionId: connectionId, database: database, schema: schema, table: table)
    }

    private func key(
        column: String = "ArtistId",
        referencedTable: String = "Artist",
        referencedColumn: String = "ArtistId",
        referencedDatabase: String? = nil,
        referencedSchema: String? = nil
    ) -> VirtualForeignKey {
        VirtualForeignKey(
            column: column,
            referencedTable: referencedTable,
            referencedColumn: referencedColumn,
            referencedDatabase: referencedDatabase,
            referencedSchema: referencedSchema
        )
    }

    private func fields(of keysByScope: [TableScope: [VirtualForeignKey]]) -> [TableScope: Set<[String?]>] {
        keysByScope.mapValues { keys in
            Set(keys.map { [$0.column, $0.referencedTable, $0.referencedColumn, $0.referencedDatabase, $0.referencedSchema] })
        }
    }

    private func document(kind: String = "TableProVirtualForeignKeys", version: Int = 1, entries: String = "[]") -> Data {
        Data("{\"kind\": \"\(kind)\", \"version\": \(version), \"entries\": \(entries)}".utf8)
    }

    @Test("An export imports back without losing anything")
    func roundTripIsLossless() throws {
        let source = UUID()
        let target = UUID()
        let keysByScope: [TableScope: [VirtualForeignKey]] = [
            scope(connectionId: source): [
                key(),
                key(column: "GenreId", referencedTable: "Genre", referencedColumn: "GenreId")
            ],
            scope(connectionId: source, schema: "music", table: "Track"): [
                key(
                    column: "AlbumId",
                    referencedTable: "Album",
                    referencedColumn: "AlbumId",
                    referencedDatabase: "archive",
                    referencedSchema: "v2"
                )
            ],
            scope(connectionId: source, database: "other", table: "Invoice"): [
                key(column: "CustomerId", referencedTable: "Customer", referencedColumn: "CustomerId")
            ]
        ]

        let data = try VirtualForeignKeyTransfer.exportDocument(keysByScope)
        let decoded = try VirtualForeignKeyTransfer.decode(data)
        let restored = VirtualForeignKeyTransfer.merge(decoded.entries, into: [:], connectionId: target)

        #expect(decoded.skippedEntryCount == 0)
        let expected = Dictionary(uniqueKeysWithValues: keysByScope.map { entry in
            (
                TableScope(
                    connectionId: target,
                    database: entry.key.database,
                    schema: entry.key.schema,
                    table: entry.key.table
                ),
                entry.value
            )
        })
        #expect(fields(of: restored) == fields(of: expected))
    }

    @Test("An empty configuration exports an empty entry list")
    func emptyConfigurationExports() throws {
        let data = try VirtualForeignKeyTransfer.exportDocument([:])

        let decoded = try VirtualForeignKeyTransfer.decode(data)

        #expect(decoded.entries.isEmpty)
        #expect(decoded.skippedEntryCount == 0)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"entries\" : [") || text.contains("\"entries\" : []"))
        #expect(text.contains("\"kind\" : \"TableProVirtualForeignKeys\""))
        #expect(text.contains("\"version\" : 1"))
    }

    @Test("A file of another version is refused by name")
    func unsupportedVersionIsRefused() {
        #expect(throws: VirtualForeignKeyTransferError.unsupportedVersion(2)) {
            try VirtualForeignKeyTransfer.decode(document(version: 2))
        }
    }

    @Test("A file of another kind is refused")
    func wrongKindIsRefused() {
        #expect(throws: VirtualForeignKeyTransferError.unrecognizedKind) {
            try VirtualForeignKeyTransfer.decode(document(kind: "SomethingElse"))
        }
    }

    @Test("A file that is not JSON is refused")
    func unreadableFileIsRefused() {
        #expect(throws: VirtualForeignKeyTransferError.unreadableFile) {
            try VirtualForeignKeyTransfer.decode(Data("not json".utf8))
        }
    }

    @Test("A broken entry is skipped and counted, the rest import")
    func brokenEntriesAreSkippedAndCounted() throws {
        let entries = """
        [
            {"table": "orders", "column": "user_id", "referencedTable": "users", "referencedColumn": "id"},
            {"table": "orders", "column": "shop_id", "referencedTable": "shops"},
            {"table": "", "column": "x", "referencedTable": "y", "referencedColumn": "z"},
            "garbage",
            {"database": "shop", "table": "orders", "column": "country", "referencedTable": "countries", "referencedColumn": "code"}
        ]
        """

        let decoded = try VirtualForeignKeyTransfer.decode(document(entries: entries))

        #expect(decoded.entries.map(\.column) == ["user_id", "country"])
        #expect(decoded.skippedEntryCount == 3)
    }

    @Test("An imported entry overrides the key on its column and keeps every other key")
    func mergeOverridesByScopeAndColumn() throws {
        let connection = UUID()
        let overridden = key()
        let untouched = key(column: "GenreId", referencedTable: "Genre", referencedColumn: "GenreId")
        let otherTable = scope(connectionId: connection, table: "Track")
        let otherTableKey = key(column: "AlbumId", referencedTable: "Album", referencedColumn: "AlbumId")
        let existing: [TableScope: [VirtualForeignKey]] = [
            scope(connectionId: connection): [overridden, untouched],
            otherTable: [otherTableKey]
        ]
        let imported = VirtualForeignKeyTransferEntry(
            database: "chinook",
            schema: nil,
            table: "Album",
            column: "ArtistId",
            referencedDatabase: "archive",
            referencedSchema: nil,
            referencedTable: "ArtistHistory",
            referencedColumn: "Id"
        )

        let merged = VirtualForeignKeyTransfer.merge([imported], into: existing, connectionId: connection)

        let albumKeys = try #require(merged[scope(connectionId: connection)])
        let replaced = try #require(albumKeys.first { $0.column == "ArtistId" })
        #expect(replaced.id == overridden.id)
        #expect(replaced.referencedTable == "ArtistHistory")
        #expect(replaced.referencedColumn == "Id")
        #expect(replaced.referencedDatabase == "archive")
        #expect(albumKeys.contains(untouched))
        #expect(merged[otherTable] == [otherTableKey])
    }

    @Test("An import adds new scopes and never deletes existing ones")
    func mergeAddsWithoutDeleting() throws {
        let connection = UUID()
        let existingScope = scope(connectionId: connection)
        let existingKey = key()
        let imported = VirtualForeignKeyTransferEntry(
            database: "other",
            schema: "sales",
            table: "Invoice",
            column: "CustomerId",
            referencedDatabase: nil,
            referencedSchema: nil,
            referencedTable: "Customer",
            referencedColumn: "CustomerId"
        )

        let merged = VirtualForeignKeyTransfer.merge(
            [imported],
            into: [existingScope: [existingKey]],
            connectionId: connection
        )

        #expect(merged[existingScope] == [existingKey])
        let added = try #require(
            merged[TableScope(connectionId: connection, database: "other", schema: "sales", table: "Invoice")]
        )
        #expect(added.map(\.column) == ["CustomerId"])
        #expect(added.map(\.referencedTable) == ["Customer"])
    }

    @Test("An empty database or schema in the file reads as none")
    func emptyContainerStringsNormalizeToNil() throws {
        let entries = """
        [{"database": "", "schema": "", "table": "orders", "column": "user_id",
          "referencedDatabase": "", "referencedSchema": "",
          "referencedTable": "users", "referencedColumn": "id"}]
        """

        let decoded = try VirtualForeignKeyTransfer.decode(document(entries: entries))

        let entry = try #require(decoded.entries.first)
        #expect(entry.database == nil)
        #expect(entry.schema == nil)
        #expect(entry.referencedDatabase == nil)
        #expect(entry.referencedSchema == nil)
    }
}
