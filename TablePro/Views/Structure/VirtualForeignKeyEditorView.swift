//
//  VirtualForeignKeyEditorView.swift
//  TablePro
//
//  The sheet that configures one virtual foreign key: a column of this table pointing at a
//  column of another table in the same database and schema.
//

import Combine
import SwiftUI

/// What the editor stages before it is saved, kept apart from the view so completeness, the
/// one-key-per-column rule and the upsert are plain functions.
struct VirtualForeignKeyDraft: Equatable {
    var column = ""
    var referencedTable = ""
    var referencedColumn = ""

    init() {}

    init(_ key: VirtualForeignKey) {
        column = key.column
        referencedTable = key.referencedTable
        referencedColumn = key.referencedColumn
    }

    var isComplete: Bool {
        !trimmed(column).isEmpty && !trimmed(referencedTable).isEmpty && !trimmed(referencedColumn).isEmpty
    }

    /// The column is the key: a second virtual foreign key on a column one already covers could
    /// never both apply, so it is refused rather than stored.
    func conflicts(with keys: [VirtualForeignKey], editing edited: VirtualForeignKey?) -> Bool {
        let name = trimmed(column)
        return keys.contains { $0.column == name && $0.id != edited?.id }
    }

    /// The stored key, or nil while the draft is incomplete or collides with another key's column.
    /// A target chosen here lives in the table's own database and schema, so those fields stay nil;
    /// an edited key keeps its stored container only while its referenced table is unchanged.
    func validated(against keys: [VirtualForeignKey], editing edited: VirtualForeignKey?) -> VirtualForeignKey? {
        guard isComplete, !conflicts(with: keys, editing: edited) else { return nil }
        let table = trimmed(referencedTable)
        let keepsTarget = edited?.referencedTable == table
        return VirtualForeignKey(
            id: edited?.id ?? UUID(),
            column: trimmed(column),
            referencedTable: table,
            referencedColumn: trimmed(referencedColumn),
            referencedDatabase: keepsTarget ? edited?.referencedDatabase : nil,
            referencedSchema: keepsTarget ? edited?.referencedSchema : nil
        )
    }

    static func applying(_ key: VirtualForeignKey, to keys: [VirtualForeignKey]) -> [VirtualForeignKey] {
        guard let index = keys.firstIndex(where: { $0.id == key.id }) else { return keys + [key] }
        var updated = keys
        updated[index] = key
        return updated
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
    }
}

/// The referenced table and column lists, read through the same `ForeignKeyReferenceMenus` the
/// Foreign Keys grid uses so the loading, failure and view-filtering behavior cannot drift.
@MainActor
private final class VirtualForeignKeyReferenceLists: ObservableObject {
    @Published private(set) var revision = 0

    private let menus: ForeignKeyReferenceMenus

    init(connection: DatabaseConnection, scope: DatabaseScope) {
        menus = ForeignKeyReferenceMenus(connectionId: connection.id, databaseType: connection.type)
        menus.origin = scope
        menus.schemaName = scope.schema
        menus.onListsChanged = { [weak self] in self?.revision += 1 }
    }

    func tableOptions() -> [GridMenuOption] {
        menus.options(columnIndex: 2, foreignKey: .placeholder(), tableColumns: []) ?? []
    }

    func referencedColumnOptions(for table: String) -> [GridMenuOption] {
        var key = EditableForeignKeyDefinition.placeholder()
        key.referencedTable = table
        return menus.options(columnIndex: 3, foreignKey: key, tableColumns: []) ?? []
    }

    func prefetchColumns(of table: String) {
        menus.prefetchReferencedColumns(of: table, schema: nil)
    }
}

struct VirtualForeignKeyEditorView: View {
    let tableName: String
    let tableColumns: [String]
    let existingKeys: [VirtualForeignKey]
    let onSave: (VirtualForeignKey) -> Void
    let onCancel: () -> Void

    private let editing: VirtualForeignKey?

    @StateObject private var lists: VirtualForeignKeyReferenceLists
    @State private var draft: VirtualForeignKeyDraft
    @State private var typesTableName = false
    @State private var typesColumnName = false

    init(
        connection: DatabaseConnection,
        scope: DatabaseScope,
        tableName: String,
        tableColumns: [String],
        existingKeys: [VirtualForeignKey],
        editing: VirtualForeignKey?,
        onSave: @escaping (VirtualForeignKey) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.tableName = tableName
        self.tableColumns = tableColumns
        self.existingKeys = existingKeys
        self.editing = editing
        self.onSave = onSave
        self.onCancel = onCancel
        _lists = StateObject(wrappedValue: VirtualForeignKeyReferenceLists(connection: connection, scope: scope))
        _draft = State(initialValue: editing.map(VirtualForeignKeyDraft.init) ?? VirtualForeignKeyDraft())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fields
            if columnConflict {
                Divider()
                conflictNote
            }
        }
        .frame(width: 440)
        .onAppear {
            _ = lists.tableOptions()
            if !draft.referencedTable.isEmpty {
                lists.prefetchColumns(of: draft.referencedTable)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(editing == nil ? "New Virtual Foreign Key" : "Edit Virtual Foreign Key")
                .font(.headline)
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("virtual-fk-editor-cancel")
            Button("Save") {
                if let key = draft.validated(against: existingKeys, editing: editing) { onSave(key) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(draft.validated(against: existingKeys, editing: editing) == nil)
            .accessibilityIdentifier("virtual-fk-editor-save")
        }
        .padding()
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(String(localized: "Column")) {
                Picker(String(localized: "Column"), selection: $draft.column) {
                    if draft.column.isEmpty {
                        Text(String(localized: "Choose Column")).tag("")
                    }
                    ForEach(columnChoices, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("virtual-fk-editor-column")
            }
            LabeledContent(String(localized: "Ref Table")) {
                referenceControl(
                    value: draft.referencedTable,
                    placeholder: String(localized: "Choose Table"),
                    options: lists.tableOptions(),
                    typesName: $typesTableName,
                    identifier: "virtual-fk-editor-ref-table",
                    text: tableBinding,
                    onSelect: selectTable
                )
            }
            LabeledContent(String(localized: "Ref Column")) {
                referenceControl(
                    value: draft.referencedColumn,
                    placeholder: String(localized: "Choose Column"),
                    options: lists.referencedColumnOptions(for: draft.referencedTable),
                    typesName: $typesColumnName,
                    identifier: "virtual-fk-editor-ref-column",
                    text: $draft.referencedColumn,
                    onSelect: { draft.referencedColumn = $0 }
                )
                .disabled(draft.referencedTable.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func referenceControl(
        value: String,
        placeholder: String,
        options: [GridMenuOption],
        typesName: Binding<Bool>,
        identifier: String,
        text: Binding<String>,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        if typesName.wrappedValue {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(identifier)
        } else {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { entry in
                    switch entry.element {
                    case .sectionHeader(let title):
                        Text(title)
                    case .value(let title, _):
                        Button(title) { onSelect(title) }
                    case .clear(let title):
                        Button(title) { onSelect("") }
                    case .custom(let title):
                        Button(title) { typesName.wrappedValue = true }
                    }
                }
            } label: {
                Text(value.isEmpty ? placeholder : value)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier(identifier)
        }
    }

    private var columnChoices: [String] {
        let names = tableColumns.filter { !$0.isEmpty }
        guard !draft.column.isEmpty, !names.contains(draft.column) else { return names }
        return names + [draft.column]
    }

    private var columnConflict: Bool {
        !draft.column.isEmpty && draft.conflicts(with: existingKeys, editing: editing)
    }

    private var conflictNote: some View {
        Label {
            Text(String(localized: "This column already has a virtual foreign key."))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .accessibilityIdentifier("virtual-fk-editor-conflict")
    }

    private var tableBinding: Binding<String> {
        Binding(
            get: { draft.referencedTable },
            set: { selectTable($0) }
        )
    }

    private func selectTable(_ name: String) {
        guard name != draft.referencedTable else { return }
        draft.referencedTable = name
        draft.referencedColumn = ""
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        lists.prefetchColumns(of: name)
    }
}
