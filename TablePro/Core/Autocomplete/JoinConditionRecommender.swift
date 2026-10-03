//
//  JoinConditionRecommender.swift
//  TablePro
//
//  Pure foreign-key-driven join condition recommendation for the ON clause
//

import Foundation

/// Recommends complete join conditions (`o.user_id = u.id`) for the ON clause of a JOIN, from the
/// foreign keys, real and virtual alike, between the joined tables. Pure: everything it reads
/// arrives as input, so it never asks a store, an actor, or the database.
enum JoinConditionRecommender {
    struct Suggestion: Hashable, Sendable {
        let conditionText: String
        let foreignKeyName: String
        let isVirtual: Bool
    }

    /// Conditions joining `target`, the table of the JOIN whose ON clause is being completed,
    /// against each other table in scope. Direction-agnostic: a key owned by either side of a pair
    /// yields a condition, spelled with the key's owning column on the left. A pair with no key
    /// between it yields nothing, so no suggestion is ever a guess from column names.
    ///
    /// `foreignKeysByTable` is keyed by lowercased table name and holds each table's outgoing keys.
    /// A composite key arrives as several entries sharing one constraint name and is skipped whole.
    static func suggestions(
        target: TableReference,
        others: [TableReference],
        foreignKeysByTable: [String: [ForeignKeyInfo]]
    ) -> [Suggestion] {
        guard !target.isDerived else { return [] }

        let targetKeys = singleColumnKeys(in: foreignKeysByTable, of: target)
        var results: [Suggestion] = []
        var seen = Set<String>()

        for other in others {
            guard !other.isDerived else { continue }
            guard other.identifier.caseInsensitiveCompare(target.identifier) != .orderedSame else { continue }

            for key in targetKeys where references(key, other) {
                append(owner: target, key: key, referenced: other, into: &results, seen: &seen)
            }
            for key in singleColumnKeys(in: foreignKeysByTable, of: other) where references(key, target) {
                append(owner: other, key: key, referenced: target, into: &results, seen: &seen)
            }
        }

        return results
    }

    private static func singleColumnKeys(
        in foreignKeysByTable: [String: [ForeignKeyInfo]],
        of side: TableReference
    ) -> [ForeignKeyInfo] {
        let keys = foreignKeysByTable[side.tableName.lowercased()] ?? []
        guard !keys.isEmpty else { return [] }

        var columnsPerConstraint: [String: Int] = [:]
        for key in keys {
            columnsPerConstraint[key.name, default: 0] += 1
        }
        return keys
            .filter { columnsPerConstraint[$0.name] == 1 }
            .sorted { $0.column.lowercased() < $1.column.lowercased() }
    }

    private static func references(_ key: ForeignKeyInfo, _ side: TableReference) -> Bool {
        guard key.referencedTable.caseInsensitiveCompare(side.tableName) == .orderedSame else { return false }
        guard let keySchema = key.referencedSchema, !keySchema.isEmpty,
              let sideSchema = side.schema, !sideSchema.isEmpty else { return true }
        return keySchema.caseInsensitiveCompare(sideSchema) == .orderedSame
    }

    private static func append(
        owner: TableReference,
        key: ForeignKeyInfo,
        referenced: TableReference,
        into results: inout [Suggestion],
        seen: inout Set<String>
    ) {
        let condition = "\(owner.identifier).\(key.column) = \(referenced.identifier).\(key.referencedColumn)"
        guard seen.insert(condition.lowercased()).inserted else { return }
        results.append(Suggestion(conditionText: condition, foreignKeyName: key.name, isVirtual: key.isVirtual))
    }
}
