//
//  VirtualForeignKeyStore.swift
//  TablePro
//

import Foundation

@MainActor
internal final class VirtualForeignKeyStore: TableScopedSettingsStore {
    static let shared = VirtualForeignKeyStore()

    private static let keyPrefix = PreferenceKeys.virtualForeignKeysPrefix

    private let store: KeyValueStore

    init(defaults: KeyValueStore = AppStorageEnvironment.shared.defaults) {
        store = defaults
    }

    func virtualForeignKeys(for scope: TableScope) -> [VirtualForeignKey] {
        guard let data = store.dataValue(forKey: PreferenceKeys.virtualForeignKeys(scope).name),
              let keys = try? JSONDecoder().decode([VirtualForeignKey].self, from: data) else {
            return []
        }
        return keys
    }

    func virtualForeignKeys(
        connectionId: UUID,
        database: String?,
        schema: String?
    ) -> [String: [VirtualForeignKey]] {
        let prefix = Self.keyPrefix
            + TableScope.storagePrefix(connectionId: connectionId, database: database, schema: schema)
        var keysByTable: [String: [VirtualForeignKey]] = [:]
        for storageKey in store.keys(withPrefix: prefix) {
            guard let scope = TableScope(storageComponent: String(storageKey.dropFirst(Self.keyPrefix.count))),
                  scope.database == database,
                  scope.schema == schema else { continue }
            let keys = virtualForeignKeys(for: scope)
            guard !keys.isEmpty else { continue }
            keysByTable[scope.table] = keys
        }
        return keysByTable
    }

    func allVirtualForeignKeys(connectionId: UUID) -> [TableScope: [VirtualForeignKey]] {
        let prefix = Self.keyPrefix + TableScope.storagePrefix(connectionId: connectionId)
        var keysByScope: [TableScope: [VirtualForeignKey]] = [:]
        for storageKey in store.keys(withPrefix: prefix) {
            guard let scope = TableScope(storageComponent: String(storageKey.dropFirst(Self.keyPrefix.count))),
                  scope.connectionId == connectionId else { continue }
            let keys = virtualForeignKeys(for: scope)
            guard !keys.isEmpty else { continue }
            keysByScope[scope] = keys
        }
        return keysByScope
    }

    func save(_ keys: [VirtualForeignKey], for scope: TableScope) {
        guard !keys.isEmpty else {
            store.setDataValue(nil, forKey: PreferenceKeys.virtualForeignKeys(scope).name)
            return
        }
        guard let data = try? JSONEncoder().encode(keys) else { return }
        store.setDataValue(data, forKey: PreferenceKeys.virtualForeignKeys(scope).name)
    }

    func renameTable(from oldScope: TableScope, to newScope: TableScope) {
        store.moveValue(
            fromKey: PreferenceKeys.virtualForeignKeys(oldScope).name,
            toKey: PreferenceKeys.virtualForeignKeys(newScope).name
        )
    }

    func renameContainer(
        connectionId: UUID,
        fromDatabase: String,
        fromSchema: String?,
        toDatabase: String,
        toSchema: String?
    ) {
        store.moveValues(
            withPrefix: Self.keyPrefix
                + TableScope.storagePrefix(connectionId: connectionId, database: fromDatabase, schema: fromSchema),
            toPrefix: Self.keyPrefix
                + TableScope.storagePrefix(connectionId: connectionId, database: toDatabase, schema: toSchema)
        )
    }

    func dropTable(_ scope: TableScope) {
        store.setDataValue(nil, forKey: PreferenceKeys.virtualForeignKeys(scope).name)
    }

    func dropContainer(connectionId: UUID, database: String, schema: String?) {
        store.removeValues(
            withPrefix: Self.keyPrefix
                + TableScope.storagePrefix(connectionId: connectionId, database: database, schema: schema)
        )
    }

    func purgeConnections(_ connectionIds: Set<UUID>, leavesTombstones: Bool) {
        for connectionId in connectionIds {
            store.removeValues(withPrefix: Self.keyPrefix + TableScope.storagePrefix(connectionId: connectionId))
        }
    }
}
