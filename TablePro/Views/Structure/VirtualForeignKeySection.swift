//
//  VirtualForeignKeySection.swift
//  TablePro
//
//  The Structure editor's Virtual Keys tab: relationships TablePro stores on its own,
//  never written to the database and never part of DDL or schema tracking.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct VirtualForeignKeyEditorItem: Identifiable {
    let id = UUID()
    let editing: VirtualForeignKey?
}

struct VirtualForeignKeySection: View {
    let connection: DatabaseConnection
    let scope: DatabaseScope
    let tableName: String
    let tableColumns: [String]

    @State private var keys: [VirtualForeignKey] = []
    @State private var selectedID: VirtualForeignKey.ID?
    @State private var editorItem: VirtualForeignKeyEditorItem?
    @State private var pendingDelete: VirtualForeignKey?

    private var tableScope: TableScope {
        TableScope(
            connectionId: scope.connectionId,
            database: scope.database,
            schema: scope.schema,
            table: tableName
        )
    }

    private var selectedKey: VirtualForeignKey? {
        keys.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            if keys.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: reload)
        .sheet(item: $editorItem, content: makeEditor(for:))
        .confirmationDialog(
            String(
                format: String(localized: "Remove the virtual foreign key on “%@”?"),
                pendingDelete?.column ?? ""
            ),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove"), role: .destructive) {
                if let key = pendingDelete { remove(key) }
                pendingDelete = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { pendingDelete = nil }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                editorItem = VirtualForeignKeyEditorItem(editing: nil)
            } label: {
                Label(String(localized: "Add Virtual Foreign Key"), systemImage: "plus")
            }
            .accessibilityIdentifier("virtual-fk-add")
            Button {
                if let selectedKey { editorItem = VirtualForeignKeyEditorItem(editing: selectedKey) }
            } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
            }
            .disabled(selectedKey == nil)
            .accessibilityIdentifier("virtual-fk-edit")
            Button {
                if let selectedKey { pendingDelete = selectedKey }
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            .disabled(selectedKey == nil)
            .accessibilityIdentifier("virtual-fk-delete")
            Spacer()
            Button {
                exportAllKeys()
            } label: {
                Label(String(localized: "Export All Virtual Foreign Keys…"), systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("virtual-fk-export")
            Button {
                importKeys()
            } label: {
                Label(String(localized: "Import Virtual Foreign Keys…"), systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("virtual-fk-import")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "link.badge.plus",
            title: String(localized: "No Virtual Foreign Keys"),
            description: String(
                localized: """
                Link a column of this table to another table for navigation and diagrams. \
                Stored in TablePro only, the database is never changed.
                """
            ),
            actionTitle: String(localized: "Add Virtual Foreign Key"),
            action: { editorItem = VirtualForeignKeyEditorItem(editing: nil) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        Table(keys, selection: $selectedID) {
            TableColumn(String(localized: "Column")) { key in
                Text(key.column)
            }
            .width(min: 120, ideal: 200)
            TableColumn(String(localized: "Ref Table")) { key in
                Text(key.referencedTable)
            }
            .width(min: 120, ideal: 200)
            TableColumn(String(localized: "Ref Column")) { key in
                Text(key.referencedColumn)
            }
            .width(min: 120, ideal: 200)
        }
        .contextMenu(forSelectionType: VirtualForeignKey.ID.self) { ids in
            if let key = keys.first(where: { ids.contains($0.id) }) {
                Button(String(localized: "Edit Virtual Foreign Key…")) {
                    editorItem = VirtualForeignKeyEditorItem(editing: key)
                }
                Button(String(localized: "Delete Virtual Foreign Key"), role: .destructive) {
                    pendingDelete = key
                }
            }
        } primaryAction: { ids in
            guard let key = keys.first(where: { ids.contains($0.id) }) else { return }
            editorItem = VirtualForeignKeyEditorItem(editing: key)
        }
    }

    private func makeEditor(for item: VirtualForeignKeyEditorItem) -> some View {
        VirtualForeignKeyEditorView(
            connection: connection,
            scope: scope,
            tableName: tableName,
            tableColumns: tableColumns,
            existingKeys: keys,
            editing: item.editing,
            onSave: { key in
                save(key)
                editorItem = nil
            },
            onCancel: { editorItem = nil }
        )
    }

    private func reload() {
        keys = VirtualForeignKeyStore.shared.virtualForeignKeys(for: tableScope)
    }

    private func save(_ key: VirtualForeignKey) {
        keys = VirtualForeignKeyDraft.applying(key, to: keys)
        VirtualForeignKeyStore.shared.save(keys, for: tableScope)
        selectedID = key.id
    }

    private func remove(_ key: VirtualForeignKey) {
        keys.removeAll { $0.id == key.id }
        VirtualForeignKeyStore.shared.save(keys, for: tableScope)
        if selectedID == key.id { selectedID = nil }
    }

    private func exportAllKeys() {
        guard let window = AlertHelper.resolveWindow(nil) else { return }
        let connectionId = scope.connectionId
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = connection.name + " Virtual Foreign Keys.json"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let keysByScope = VirtualForeignKeyStore.shared.allVirtualForeignKeys(connectionId: connectionId)
                let data = try VirtualForeignKeyTransfer.exportDocument(keysByScope)
                try data.write(to: url)
            } catch {
                AlertHelper.showErrorSheet(
                    title: String(localized: "Could not export the virtual foreign keys"),
                    message: error.localizedDescription,
                    window: window
                )
            }
        }
    }

    private func importKeys() {
        guard let window = AlertHelper.resolveWindow(nil) else { return }
        let connectionId = scope.connectionId
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let decoded = try VirtualForeignKeyTransfer.decode(Data(contentsOf: url))
                let store = VirtualForeignKeyStore.shared
                let merged = VirtualForeignKeyTransfer.merge(
                    decoded.entries,
                    into: store.allVirtualForeignKeys(connectionId: connectionId),
                    connectionId: connectionId
                )
                for (mergedScope, mergedKeys) in merged {
                    store.save(mergedKeys, for: mergedScope)
                }
                reload()
                AlertHelper.showInfoSheet(
                    title: String(localized: "Virtual Foreign Keys Imported"),
                    message: importSummary(for: decoded),
                    window: window
                )
            } catch {
                AlertHelper.showErrorSheet(
                    title: String(localized: "Could not import the virtual foreign keys"),
                    message: error.localizedDescription,
                    window: window
                )
            }
        }
    }

    private func importSummary(for decoded: VirtualForeignKeyTransferDecodeResult) -> String {
        var lines = [
            String(
                format: String(localized: "%d virtual foreign keys were imported into this connection."),
                decoded.entries.count
            )
        ]
        if decoded.skippedEntryCount > 0 {
            lines.append(
                String(
                    format: String(localized: "%d invalid entries were skipped."),
                    decoded.skippedEntryCount
                )
            )
        }
        return lines.joined(separator: "\n")
    }
}
