import Foundation
import Testing

@testable import TablePro

@MainActor
struct VirtualForeignKeyStoreTests {
    private func makeStore() throws -> VirtualForeignKeyStore {
        let defaults = try #require(UserDefaults(suiteName: "VirtualForeignKeyStoreTests.\(UUID().uuidString)"))
        return VirtualForeignKeyStore(defaults: defaults)
    }

    private func scope(
        connectionId: UUID,
        database: String? = "chinook",
        schema: String? = nil,
        table: String = "Album"
    ) -> TableScope {
        TableScope(connectionId: connectionId, database: database, schema: schema, table: table)
    }

    private func key(column: String = "ArtistId", referencedTable: String = "Artist") -> VirtualForeignKey {
        VirtualForeignKey(column: column, referencedTable: referencedTable, referencedColumn: "ArtistId")
    }

    @Test("A table with nothing stored answers an empty list")
    func unsetScopeAnswersEmpty() throws {
        let store = try makeStore()
        #expect(store.virtualForeignKeys(for: scope(connectionId: UUID())).isEmpty)
    }

    @Test("Saved keys come back in order")
    func savedKeysRoundTrip() throws {
        let store = try makeStore()
        let target = scope(connectionId: UUID())
        let keys = [key(), key(column: "GenreId", referencedTable: "Genre")]

        store.save(keys, for: target)

        #expect(store.virtualForeignKeys(for: target) == keys)
    }

    @Test("Saving an empty list removes the stored keys")
    func savingEmptyRemovesTheEntry() throws {
        let store = try makeStore()
        let target = scope(connectionId: UUID())
        store.save([key()], for: target)

        store.save([], for: target)

        #expect(store.virtualForeignKeys(for: target).isEmpty)
    }

    @Test("Each table keeps its own keys")
    func keysAreScopedToTheTable() throws {
        let store = try makeStore()
        let connection = UUID()
        let albumKey = key()
        let trackKey = key(column: "AlbumId", referencedTable: "Album")
        let otherDatabaseKey = key(column: "GenreId", referencedTable: "Genre")
        store.save([albumKey], for: scope(connectionId: connection))
        store.save([trackKey], for: scope(connectionId: connection, table: "Track"))
        store.save([otherDatabaseKey], for: scope(connectionId: connection, database: "other"))

        #expect(store.virtualForeignKeys(for: scope(connectionId: connection)) == [albumKey])
        #expect(store.virtualForeignKeys(for: scope(connectionId: connection, table: "Track")) == [trackKey])
        #expect(store.virtualForeignKeys(for: scope(connectionId: connection, database: "other")) == [otherDatabaseKey])
    }

    @Test("A container read answers every table's keys grouped by table name")
    func containerReadGroupsByTable() throws {
        let store = try makeStore()
        let connection = UUID()
        let albumKeys = [key()]
        let trackKeys = [key(column: "AlbumId", referencedTable: "Album"), key(column: "GenreId", referencedTable: "Genre")]
        store.save(albumKeys, for: scope(connectionId: connection))
        store.save(trackKeys, for: scope(connectionId: connection, table: "Track"))

        let read = store.virtualForeignKeys(connectionId: connection, database: "chinook", schema: nil)

        #expect(read == ["Album": albumKeys, "Track": trackKeys])
    }

    @Test("A container read leaves other databases, schemas and connections out")
    func containerReadStaysInsideItsContainer() throws {
        let store = try makeStore()
        let connection = UUID()
        let other = UUID()
        let inside = [key()]
        store.save(inside, for: scope(connectionId: connection))
        store.save([key(column: "GenreId", referencedTable: "Genre")], for: scope(connectionId: connection, database: "other"))
        store.save([key(column: "MediaTypeId", referencedTable: "MediaType")], for: scope(connectionId: connection, schema: "music"))
        store.save([key(column: "CustomerId", referencedTable: "Customer")], for: scope(connectionId: other))

        let read = store.virtualForeignKeys(connectionId: connection, database: "chinook", schema: nil)

        #expect(read == ["Album": inside])
    }

    @Test("A schema-scoped container read answers only that schema")
    func containerReadMatchesTheSchema() throws {
        let store = try makeStore()
        let connection = UUID()
        let inMusic = [key()]
        store.save(inMusic, for: scope(connectionId: connection, schema: "music"))
        store.save([key(column: "GenreId", referencedTable: "Genre")], for: scope(connectionId: connection, schema: "catalog"))

        let read = store.virtualForeignKeys(connectionId: connection, database: "chinook", schema: "music")

        #expect(read == ["Album": inMusic])
    }

    @Test("A container with nothing stored answers an empty dictionary")
    func emptyContainerReadAnswersEmpty() throws {
        let store = try makeStore()
        #expect(store.virtualForeignKeys(connectionId: UUID(), database: "chinook", schema: nil).isEmpty)
    }

    @Test("A connection read answers every database, schema and table it stores")
    func connectionReadSpansEveryContainer() throws {
        let store = try makeStore()
        let connection = UUID()
        let other = UUID()
        let albumScope = scope(connectionId: connection)
        let trackScope = scope(connectionId: connection, schema: "music", table: "Track")
        let invoiceScope = scope(connectionId: connection, database: "other", table: "Invoice")
        let albumKeys = [key()]
        let trackKeys = [key(column: "AlbumId", referencedTable: "Album")]
        let invoiceKeys = [key(column: "CustomerId", referencedTable: "Customer")]
        store.save(albumKeys, for: albumScope)
        store.save(trackKeys, for: trackScope)
        store.save(invoiceKeys, for: invoiceScope)
        store.save([key(column: "GenreId", referencedTable: "Genre")], for: scope(connectionId: other))

        let read = store.allVirtualForeignKeys(connectionId: connection)

        #expect(read == [albumScope: albumKeys, trackScope: trackKeys, invoiceScope: invoiceKeys])
    }

    @Test("A connection with nothing stored answers an empty dictionary")
    func emptyConnectionReadAnswersEmpty() throws {
        let store = try makeStore()
        store.save([key()], for: scope(connectionId: UUID()))

        #expect(store.allVirtualForeignKeys(connectionId: UUID()).isEmpty)
    }

    @Test("A name with a dot or a quote survives the key encoding")
    func awkwardNamesSurvive() throws {
        let store = try makeStore()
        let target = scope(connectionId: UUID(), schema: "public.v2", table: "user\"s")
        let stored = key()

        store.save([stored], for: target)

        #expect(store.virtualForeignKeys(for: target) == [stored])
        #expect(store.virtualForeignKeys(for: scope(connectionId: target.connectionId)).isEmpty)
        #expect(
            store.virtualForeignKeys(connectionId: target.connectionId, database: "chinook", schema: "public.v2")
                == ["user\"s": [stored]]
        )
    }

    @Test("A table rename moves its keys and leaves a longer name alone")
    func renameTableMovesOnlyThatTable() throws {
        let store = try makeStore()
        let connection = UUID()
        let moved = key()
        let kept = key(column: "GenreId", referencedTable: "Genre")
        store.save([moved], for: scope(connectionId: connection))
        store.save([kept], for: scope(connectionId: connection, table: "Album_archive"))

        store.renameTable(
            from: scope(connectionId: connection),
            to: scope(connectionId: connection, table: "Record")
        )

        #expect(store.virtualForeignKeys(for: scope(connectionId: connection)).isEmpty)
        #expect(store.virtualForeignKeys(for: scope(connectionId: connection, table: "Record")) == [moved])
        #expect(store.virtualForeignKeys(for: scope(connectionId: connection, table: "Album_archive")) == [kept])
    }

    @Test("A schema rename moves every table in it and nothing outside it")
    func renameContainerMovesTheSchema() throws {
        let store = try makeStore()
        let connection = UUID()
        let other = UUID()
        let inMusic = key()
        let alsoInMusic = key(column: "GenreId", referencedTable: "Genre")
        let inOldSchema = key(column: "MediaTypeId", referencedTable: "MediaType")
        let inOtherConnection = key(column: "CustomerId", referencedTable: "Customer")
        store.save([inMusic], for: scope(connectionId: connection, schema: "music"))
        store.save([alsoInMusic], for: scope(connectionId: connection, schema: "music", table: "Track"))
        store.save([inOldSchema], for: scope(connectionId: connection, schema: "music_old"))
        store.save([inOtherConnection], for: scope(connectionId: other, schema: "music"))

        store.renameContainer(
            connectionId: connection, fromDatabase: "chinook", fromSchema: "music",
            toDatabase: "chinook", toSchema: "catalog"
        )

        #expect(store.virtualForeignKeys(for: scope(connectionId: connection, schema: "catalog")) == [inMusic])
        #expect(
            store.virtualForeignKeys(for: scope(connectionId: connection, schema: "catalog", table: "Track"))
                == [alsoInMusic]
        )
        #expect(store.virtualForeignKeys(for: scope(connectionId: connection, schema: "music")).isEmpty)
        #expect(store.virtualForeignKeys(for: scope(connectionId: connection, schema: "music_old")) == [inOldSchema])
        #expect(store.virtualForeignKeys(for: scope(connectionId: other, schema: "music")) == [inOtherConnection])
    }

    @Test("Dropping a table forgets its keys and leaves its siblings alone")
    func dropTableForgetsOnlyThatTable() throws {
        let store = try makeStore()
        let connection = UUID()
        let dropped = scope(connectionId: connection)
        let sibling = scope(connectionId: connection, table: "Track")
        let siblingKey = key(column: "AlbumId", referencedTable: "Album")
        store.save([key()], for: dropped)
        store.save([siblingKey], for: sibling)

        store.dropTable(dropped)

        #expect(store.virtualForeignKeys(for: dropped).isEmpty)
        #expect(store.virtualForeignKeys(for: sibling) == [siblingKey])
    }

    @Test("Dropping a database forgets every table under it and nothing outside it")
    func dropContainerForgetsTheWholeDatabase() throws {
        let store = try makeStore()
        let connection = UUID()
        let inside = scope(connectionId: connection)
        let alsoInside = scope(connectionId: connection, table: "Track")
        let outside = scope(connectionId: connection, database: "other")
        let outsideKey = key(column: "GenreId", referencedTable: "Genre")
        store.save([key()], for: inside)
        store.save([key(column: "AlbumId", referencedTable: "Album")], for: alsoInside)
        store.save([outsideKey], for: outside)

        store.dropContainer(connectionId: connection, database: "chinook", schema: nil)

        #expect(store.virtualForeignKeys(for: inside).isEmpty)
        #expect(store.virtualForeignKeys(for: alsoInside).isEmpty)
        #expect(store.virtualForeignKeys(for: outside) == [outsideKey])
    }

    @Test("Deleting a connection removes its keys and keeps every other connection's")
    func purgeConnectionsRemovesOnlyThatConnection() throws {
        let store = try makeStore()
        let connection = UUID()
        let other = UUID()
        let keptKey = key(column: "CustomerId", referencedTable: "Customer")
        store.save([key()], for: scope(connectionId: connection))
        store.save([key(column: "AlbumId", referencedTable: "Album")], for: scope(connectionId: connection, table: "Track"))
        store.save([keptKey], for: scope(connectionId: other))

        store.purgeConnections([connection], leavesTombstones: true)

        #expect(store.virtualForeignKeys(for: scope(connectionId: connection)).isEmpty)
        #expect(store.virtualForeignKeys(for: scope(connectionId: connection, table: "Track")).isEmpty)
        #expect(store.virtualForeignKeys(for: scope(connectionId: other)) == [keptKey])
    }
}
