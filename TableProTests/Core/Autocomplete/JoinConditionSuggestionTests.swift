//
//  JoinConditionSuggestionTests.swift
//  TableProTests
//

import Foundation
@testable import TablePro
import Testing

@MainActor
struct JoinConditionSuggestionTests {
    private let analyzer = SQLContextAnalyzer()

    private func ref(_ table: String, _ alias: String? = nil, schema: String? = nil) -> TableReference {
        TableReference(tableName: table, alias: alias, schema: schema)
    }

    private func fk(
        name: String = "fk_orders_users",
        column: String = "user_id",
        referencedTable: String = "users",
        referencedColumn: String = "id",
        referencedSchema: String? = nil,
        isVirtual: Bool = false
    ) -> ForeignKeyInfo {
        ForeignKeyInfo(
            name: name,
            column: column,
            referencedTable: referencedTable,
            referencedColumn: referencedColumn,
            referencedSchema: referencedSchema,
            isVirtual: isVirtual
        )
    }

    // MARK: - End to end: ON clause completion

    @Test("ON clause suggests equality from a single-column foreign key between the joined tables")
    func suggestsConditionFromForeignKey() async {
        let connectionId = UUID()
        let connection = TestFixtures.makeConnection(id: connectionId, type: .mysql)
        let scope = DatabaseScope(connectionId: connectionId, database: "shop", schema: nil)
        SchemaForeignKeyStore.shared.store(["orders": [fk()]], for: scope)

        let schemaProvider = SQLSchemaProvider()
        await schemaProvider.resetForDatabase(
            "shop",
            tables: [TestFixtures.makeTableInfo(name: "orders"), TestFixtures.makeTableInfo(name: "users")],
            driver: MockDatabaseDriver(connection: connection),
            connection: connection
        )
        await schemaProvider.waitForForeignKeySnapshot()
        let completion = SQLCompletionProvider(schemaProvider: schemaProvider, databaseType: .mysql)

        let text = "SELECT * FROM orders o JOIN users u ON "
        let (items, context) = await completion.getCompletions(
            text: text, cursorPosition: (text as NSString).length
        )

        let relations = items.filter { $0.kind == .relation }
        #expect(context.clauseType == .on)
        #expect(relations.map(\.label) == ["o.user_id = u.id"])
        #expect(relations.first?.insertText == "o.user_id = u.id")
        #expect(relations.first?.detail == "fk_orders_users")
        #expect(items.first?.label == "o.user_id = u.id")
    }

    @Test("A virtual foreign key suggests the same way and says so in the detail")
    func virtualForeignKeySuggests() async {
        let connectionId = UUID()
        let connection = TestFixtures.makeConnection(id: connectionId, type: .mysql)
        let tableScope = TableScope(connectionId: connectionId, database: "shop", schema: nil, table: "orders")
        VirtualForeignKeyStore.shared.save(
            [VirtualForeignKey(column: "user_id", referencedTable: "users", referencedColumn: "id")],
            for: tableScope
        )
        defer { VirtualForeignKeyStore.shared.dropTable(tableScope) }

        let schemaProvider = SQLSchemaProvider()
        await schemaProvider.resetForDatabase(
            "shop",
            tables: [TestFixtures.makeTableInfo(name: "orders"), TestFixtures.makeTableInfo(name: "users")],
            driver: MockDatabaseDriver(connection: connection),
            connection: connection
        )
        await schemaProvider.waitForForeignKeySnapshot()
        let completion = SQLCompletionProvider(schemaProvider: schemaProvider, databaseType: .mysql)

        let text = "SELECT * FROM orders o JOIN users u ON "
        let (items, _) = await completion.getCompletions(
            text: text, cursorPosition: (text as NSString).length
        )

        let relations = items.filter { $0.kind == .relation }
        #expect(relations.map(\.label) == ["o.user_id = u.id"])
        #expect(relations.first?.detail == "virtual foreign key")
    }

    // MARK: - Recommender: direction and spelling

    @Test("The suggestion is the same whichever side of the key is joined last")
    func reversedJoinOrderSuggestsSameCondition() {
        let keys = ["orders": [fk()]]

        let joiningUsers = JoinConditionRecommender.suggestions(
            target: ref("users", "u"), others: [ref("orders", "o")], foreignKeysByTable: keys
        )
        let joiningOrders = JoinConditionRecommender.suggestions(
            target: ref("orders", "o"), others: [ref("users", "u")], foreignKeysByTable: keys
        )

        #expect(joiningUsers.map(\.conditionText) == ["o.user_id = u.id"])
        #expect(joiningOrders.map(\.conditionText) == ["o.user_id = u.id"])
    }

    @Test("Unaliased tables are spelled by table name")
    func unaliasedTablesUseTableNames() {
        let suggestions = JoinConditionRecommender.suggestions(
            target: ref("users"), others: [ref("orders")], foreignKeysByTable: ["orders": [fk()]]
        )

        #expect(suggestions.map(\.conditionText) == ["orders.user_id = users.id"])
    }

    // MARK: - Recommender: candidate sets

    @Test("A real and a virtual key on different columns each yield a candidate")
    func realAndVirtualKeysBothSuggest() {
        let keys = [
            "orders": [
                fk(),
                fk(name: "virtual_owner_id_users", column: "owner_id", isVirtual: true)
            ]
        ]

        let suggestions = JoinConditionRecommender.suggestions(
            target: ref("users", "u"), others: [ref("orders", "o")], foreignKeysByTable: keys
        )

        #expect(suggestions.map(\.conditionText) == ["o.owner_id = u.id", "o.user_id = u.id"])
        #expect(suggestions.map(\.isVirtual) == [true, false])
    }

    @Test("A real key covers the virtual key on the same column")
    func realKeyCoversVirtualOnSameColumn() {
        let merged = VirtualForeignKeyMerge.merged(
            real: ["user_id": fk()],
            virtual: [VirtualForeignKey(column: "user_id", referencedTable: "users", referencedColumn: "uid")]
        )
        let keys = ["orders": merged.values.sorted { $0.column < $1.column }]

        let suggestions = JoinConditionRecommender.suggestions(
            target: ref("users", "u"), others: [ref("orders", "o")], foreignKeysByTable: keys
        )

        #expect(suggestions.map(\.conditionText) == ["o.user_id = u.id"])
        #expect(suggestions.first?.isVirtual == false)
        #expect(suggestions.first?.foreignKeyName == "fk_orders_users")
    }

    @Test("No key between the joined tables suggests nothing")
    func noForeignKeyNoSuggestion() {
        let suggestions = JoinConditionRecommender.suggestions(
            target: ref("users", "u"), others: [ref("orders", "o")], foreignKeysByTable: [:]
        )

        #expect(suggestions.isEmpty)
    }

    @Test("A key between tables already joined earlier is not re-suggested for the current ON")
    func chainedJoinPairsOnlyCurrentSides() {
        let keys = ["order_items": [fk(name: "fk_items_orders", column: "order_id", referencedTable: "orders")]]

        let suggestions = JoinConditionRecommender.suggestions(
            target: ref("products", "p"),
            others: [ref("orders", "o"), ref("order_items", "i")],
            foreignKeysByTable: keys
        )

        #expect(suggestions.isEmpty)
    }

    @Test("A chained join suggests the current table's keys against every earlier table")
    func chainedJoinSuggestsCurrentTableKeys() {
        let keys = [
            "order_items": [
                fk(name: "fk_items_orders", column: "order_id", referencedTable: "orders"),
                fk(name: "fk_items_products", column: "product_id", referencedTable: "products")
            ]
        ]

        let suggestions = JoinConditionRecommender.suggestions(
            target: ref("order_items", "i"),
            others: [ref("orders", "o"), ref("products", "p")],
            foreignKeysByTable: keys
        )

        #expect(suggestions.map(\.conditionText) == ["i.order_id = o.id", "i.product_id = p.id"])
    }

    @Test("A composite real key yields no suggestion")
    func compositeKeyIsSkipped() {
        let keys = [
            "orders": [
                fk(name: "fk_composite", column: "tenant_id", referencedColumn: "tenant_id"),
                fk(name: "fk_composite", column: "user_id", referencedColumn: "id")
            ]
        ]

        let suggestions = JoinConditionRecommender.suggestions(
            target: ref("users", "u"), others: [ref("orders", "o")], foreignKeysByTable: keys
        )

        #expect(suggestions.isEmpty)
    }

    @Test("A key referencing a same-named table in another schema does not match")
    func schemaMismatchDoesNotMatch() {
        let keys = ["orders": [fk(referencedSchema: "archive")]]

        let suggestions = JoinConditionRecommender.suggestions(
            target: ref("users", "u", schema: "public"),
            others: [ref("orders", "o")],
            foreignKeysByTable: keys
        )

        #expect(suggestions.isEmpty)
    }

    // MARK: - Analyzer: which JOIN owns the ON clause

    @Test("The ON clause's join target is the joined table with its alias")
    func joinTargetCarriesAlias() {
        let text = "SELECT * FROM orders o JOIN users u ON "
        let context = analyzer.analyze(query: text, cursorPosition: (text as NSString).length)

        #expect(context.clauseType == .on)
        #expect(context.joinTarget?.tableName == "users")
        #expect(context.joinTarget?.alias == "u")
    }

    @Test("A chained join's second ON targets the table of the JOIN nearest the cursor")
    func chainedJoinTargetsNearestJoin() {
        let text = "SELECT * FROM a JOIN b ON a.x = b.y JOIN c ON "
        let context = analyzer.analyze(query: text, cursorPosition: (text as NSString).length)

        #expect(context.clauseType == .on)
        #expect(context.joinTarget?.tableName == "c")
    }

    @Test("Outside an ON clause there is no join target")
    func noJoinTargetOutsideOn() {
        let text = "SELECT * FROM orders o JOIN users u ON o.user_id = u.id WHERE "
        let context = analyzer.analyze(query: text, cursorPosition: (text as NSString).length)

        #expect(context.joinTarget == nil)
    }
}
