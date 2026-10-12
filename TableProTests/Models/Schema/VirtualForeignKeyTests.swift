import Foundation
import Testing

@testable import TablePro

struct VirtualForeignKeyTests {
    @Test("toForeignKeyInfo carries every field and marks the key virtual")
    func toForeignKeyInfoMapsEveryField() {
        let virtualKey = VirtualForeignKey(
            column: "ArtistId",
            referencedTable: "Artist",
            referencedColumn: "Id",
            referencedDatabase: "chinook",
            referencedSchema: "music"
        )

        let info = virtualKey.toForeignKeyInfo()

        #expect(info.name == "virtual_ArtistId_Artist")
        #expect(info.column == "ArtistId")
        #expect(info.referencedTable == "Artist")
        #expect(info.referencedColumn == "Id")
        #expect(info.referencedDatabase == "chinook")
        #expect(info.referencedSchema == "music")
        #expect(info.onDelete == "NO ACTION")
        #expect(info.onUpdate == "NO ACTION")
        #expect(info.isVirtual)
    }

    @Test("Optional containers stay absent when the key names none")
    func optionalContainersStayAbsent() {
        let info = VirtualForeignKey(column: "GenreId", referencedTable: "Genre", referencedColumn: "Id")
            .toForeignKeyInfo()

        #expect(info.referencedDatabase == nil)
        #expect(info.referencedSchema == nil)
    }

    @Test("Two virtual keys on one table get distinct names")
    func namesStayDistinctWithinOneTable() {
        let first = VirtualForeignKey(column: "ArtistId", referencedTable: "Artist", referencedColumn: "Id")
        let second = VirtualForeignKey(column: "GenreId", referencedTable: "Genre", referencedColumn: "Id")

        #expect(first.toForeignKeyInfo().name != second.toForeignKeyInfo().name)
    }

    @Test("A key round-trips through Codable")
    func codableRoundTrip() throws {
        let original = VirtualForeignKey(
            column: "ArtistId",
            referencedTable: "Artist",
            referencedColumn: "Id",
            referencedDatabase: "chinook",
            referencedSchema: "music"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VirtualForeignKey.self, from: data)

        #expect(decoded == original)
    }

    @Test("A list of keys round-trips through Codable")
    func codableListRoundTrip() throws {
        let originals = [
            VirtualForeignKey(column: "ArtistId", referencedTable: "Artist", referencedColumn: "Id"),
            VirtualForeignKey(column: "GenreId", referencedTable: "Genre", referencedColumn: "Id")
        ]

        let data = try JSONEncoder().encode(originals)
        let decoded = try JSONDecoder().decode([VirtualForeignKey].self, from: data)

        #expect(decoded == originals)
    }

    @Test("An existing ForeignKeyInfo construction stays non-virtual")
    func existingConstructionsStayNonVirtual() {
        let info = ForeignKeyInfo(
            name: "fk_album_artist",
            column: "ArtistId",
            referencedTable: "Artist",
            referencedColumn: "Id"
        )

        #expect(!info.isVirtual)
    }
}
