//
//  VirtualForeignKey.swift
//  TablePro
//

import Foundation

struct VirtualForeignKey: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var column: String
    var referencedTable: String
    var referencedColumn: String
    var referencedDatabase: String?
    var referencedSchema: String?

    init(
        id: UUID = UUID(),
        column: String,
        referencedTable: String,
        referencedColumn: String,
        referencedDatabase: String? = nil,
        referencedSchema: String? = nil
    ) {
        self.id = id
        self.column = column
        self.referencedTable = referencedTable
        self.referencedColumn = referencedColumn
        self.referencedDatabase = referencedDatabase
        self.referencedSchema = referencedSchema
    }

    func toForeignKeyInfo() -> ForeignKeyInfo {
        ForeignKeyInfo(
            name: "virtual_\(column)_\(referencedTable)",
            column: column,
            referencedTable: referencedTable,
            referencedColumn: referencedColumn,
            referencedDatabase: referencedDatabase,
            referencedSchema: referencedSchema,
            onDelete: "NO ACTION",
            onUpdate: "NO ACTION",
            isVirtual: true
        )
    }
}
