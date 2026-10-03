//
//  VirtualForeignKeyTransfer.swift
//  TablePro
//

import Foundation

struct VirtualForeignKeyTransferEntry: Hashable, Sendable {
    let database: String?
    let schema: String?
    let table: String
    let column: String
    let referencedDatabase: String?
    let referencedSchema: String?
    let referencedTable: String
    let referencedColumn: String
}

extension VirtualForeignKeyTransferEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case database
        case schema
        case table
        case column
        case referencedDatabase
        case referencedSchema
        case referencedTable
        case referencedColumn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        database = Self.normalized(try container.decodeIfPresent(String.self, forKey: .database))
        schema = Self.normalized(try container.decodeIfPresent(String.self, forKey: .schema))
        table = try container.decode(String.self, forKey: .table)
        column = try container.decode(String.self, forKey: .column)
        referencedDatabase = Self.normalized(try container.decodeIfPresent(String.self, forKey: .referencedDatabase))
        referencedSchema = Self.normalized(try container.decodeIfPresent(String.self, forKey: .referencedSchema))
        referencedTable = try container.decode(String.self, forKey: .referencedTable)
        referencedColumn = try container.decode(String.self, forKey: .referencedColumn)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(database, forKey: .database)
        try container.encode(schema, forKey: .schema)
        try container.encode(table, forKey: .table)
        try container.encode(column, forKey: .column)
        try container.encode(referencedDatabase, forKey: .referencedDatabase)
        try container.encode(referencedSchema, forKey: .referencedSchema)
        try container.encode(referencedTable, forKey: .referencedTable)
        try container.encode(referencedColumn, forKey: .referencedColumn)
    }

    private static func normalized(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }
}

extension VirtualForeignKeyTransferEntry {
    init(key: VirtualForeignKey, scope: TableScope) {
        self.init(
            database: scope.database,
            schema: scope.schema,
            table: scope.table,
            column: key.column,
            referencedDatabase: key.referencedDatabase,
            referencedSchema: key.referencedSchema,
            referencedTable: key.referencedTable,
            referencedColumn: key.referencedColumn
        )
    }

    var isComplete: Bool {
        !table.isEmpty && !column.isEmpty && !referencedTable.isEmpty && !referencedColumn.isEmpty
    }

    func key(id: UUID) -> VirtualForeignKey {
        VirtualForeignKey(
            id: id,
            column: column,
            referencedTable: referencedTable,
            referencedColumn: referencedColumn,
            referencedDatabase: referencedDatabase,
            referencedSchema: referencedSchema
        )
    }
}

struct VirtualForeignKeyTransferDecodeResult: Hashable, Sendable {
    let entries: [VirtualForeignKeyTransferEntry]
    let skippedEntryCount: Int
}

enum VirtualForeignKeyTransferError: Error, Hashable {
    case unreadableFile
    case unrecognizedKind
    case unsupportedVersion(Int)
}

extension VirtualForeignKeyTransferError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreadableFile, .unrecognizedKind:
            return String(localized: "The file is not a TablePro virtual foreign key export.")
        case let .unsupportedVersion(version):
            return String(
                format: String(localized: "Virtual foreign key exports of version %d are not supported."),
                version
            )
        }
    }
}

enum VirtualForeignKeyTransfer {
    static let kind = "TableProVirtualForeignKeys"
    static let currentVersion = 1

    private struct ExportDocument: Encodable {
        let kind: String
        let version: Int
        let entries: [VirtualForeignKeyTransferEntry]
    }

    private struct ImportDocument: Decodable {
        let kind: String?
        let version: Int?
        let entries: [FailableEntry]?
    }

    private struct FailableEntry: Decodable {
        let entry: VirtualForeignKeyTransferEntry?

        init(from decoder: Decoder) {
            entry = try? VirtualForeignKeyTransferEntry(from: decoder)
        }
    }

    static func exportDocument(_ keysByScope: [TableScope: [VirtualForeignKey]]) throws -> Data {
        let entries = keysByScope
            .flatMap { scope, keys in
                keys.map { VirtualForeignKeyTransferEntry(key: $0, scope: scope) }
            }
            .sorted(by: precedes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ExportDocument(kind: kind, version: currentVersion, entries: entries))
    }

    static func decode(_ data: Data) throws -> VirtualForeignKeyTransferDecodeResult {
        guard let document = try? JSONDecoder().decode(ImportDocument.self, from: data) else {
            throw VirtualForeignKeyTransferError.unreadableFile
        }
        guard document.kind == kind else {
            throw VirtualForeignKeyTransferError.unrecognizedKind
        }
        guard let version = document.version else {
            throw VirtualForeignKeyTransferError.unreadableFile
        }
        guard version == currentVersion else {
            throw VirtualForeignKeyTransferError.unsupportedVersion(version)
        }
        let candidates = document.entries ?? []
        let entries = candidates.compactMap { candidate in
            candidate.entry.flatMap { $0.isComplete ? $0 : nil }
        }
        return VirtualForeignKeyTransferDecodeResult(
            entries: entries,
            skippedEntryCount: candidates.count - entries.count
        )
    }

    static func merge(
        _ entries: [VirtualForeignKeyTransferEntry],
        into existing: [TableScope: [VirtualForeignKey]],
        connectionId: UUID
    ) -> [TableScope: [VirtualForeignKey]] {
        var merged = existing
        for entry in entries {
            let scope = TableScope(
                connectionId: connectionId,
                database: entry.database,
                schema: entry.schema,
                table: entry.table
            )
            var keys = merged[scope] ?? []
            if let index = keys.firstIndex(where: { $0.column == entry.column }) {
                keys[index] = entry.key(id: keys[index].id)
            } else {
                keys.append(entry.key(id: UUID()))
            }
            merged[scope] = keys
        }
        return merged
    }

    private static func precedes(
        _ lhs: VirtualForeignKeyTransferEntry,
        _ rhs: VirtualForeignKeyTransferEntry
    ) -> Bool {
        let left = [lhs.database ?? "", lhs.schema ?? "", lhs.table, lhs.column]
        let right = [rhs.database ?? "", rhs.schema ?? "", rhs.table, rhs.column]
        return left.lexicographicallyPrecedes(right)
    }
}
