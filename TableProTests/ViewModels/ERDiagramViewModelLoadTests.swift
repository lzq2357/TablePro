//
//  ERDiagramViewModelLoadTests.swift
//  TableProTests
//

import AppKit
@testable import TablePro
import Testing

@MainActor
struct ERDiagramViewModelLoadTests {
    private func makeCanvas(for viewModel: ERDiagramViewModel) -> DiagramScrollView {
        let scrollView = DiagramScrollView(frame: .zero)
        scrollView.allowsMagnification = true
        scrollView.minMagnification = DiagramZoom.minimum
        scrollView.maxMagnification = DiagramZoom.maximum
        scrollView.documentView = NSView(frame: CGRect(origin: .zero, size: viewModel.cachedCanvasSize))
        viewModel.viewport.attach(to: scrollView)
        scrollView.setFrameSize(CGSize(width: 900, height: 700))
        scrollView.tile()
        return scrollView
    }

    private func hasFailed(_ state: ERDiagramViewModel.LoadState) -> Bool {
        if case .failed = state { return true }
        return false
    }

    @Test("A virtual foreign key joins the merged map as a virtual entry")
    func virtualKeysMergeIn() {
        let merged = ERDiagramViewModel.mergingVirtualForeignKeys(
            ["orders": [VirtualForeignKey(column: "user_id", referencedTable: "users", referencedColumn: "id")]],
            into: [:],
            knownTables: ["orders", "users"]
        )
        let entry = merged["orders"]?.first
        #expect(entry?.isVirtual == true)
        #expect(entry?.column == "user_id")
        #expect(entry?.referencedTable == "users")
    }

    @Test("A real foreign key on the same column keeps the virtual one out")
    func realForeignKeyWins() {
        let real = TestFixtures.makeForeignKeyInfo(name: "fk_user", column: "user_id")
        let merged = ERDiagramViewModel.mergingVirtualForeignKeys(
            ["orders": [
                VirtualForeignKey(column: "user_id", referencedTable: "users", referencedColumn: "id"),
                VirtualForeignKey(column: "genre_id", referencedTable: "genres", referencedColumn: "id")
            ]],
            into: ["orders": [real]],
            knownTables: ["orders", "users", "genres"]
        )
        let entries = merged["orders"] ?? []
        #expect(entries.count == 2)
        #expect(entries.filter { $0.column == "user_id" } == [real])
        #expect(entries.first { $0.column == "genre_id" }?.isVirtual == true)
    }

    @Test("A virtual foreign key on a table the catalog no longer has stays out")
    func unknownTableStaysOut() {
        let merged = ERDiagramViewModel.mergingVirtualForeignKeys(
            ["dropped": [VirtualForeignKey(column: "user_id", referencedTable: "users", referencedColumn: "id")]],
            into: [:],
            knownTables: ["users"]
        )
        #expect(merged.isEmpty)
    }

    @Test("A load started while another is still running waits for it instead of fitting the diagram again")
    func overlappingLoadFitsOnce() async throws {
        let opening = CatalogReadHold()
        let returning = CatalogReadHold()
        let fixture = ERDiagramLoadFixture(holds: [opening, returning])
        defer { fixture.tearDown() }
        let viewModel = fixture.viewModel

        let openingLoad = Task { await viewModel.loadDiagram() }
        await opening.reached.wait()
        let returningLoad = Task { await viewModel.loadDiagram() }
        await Task.yield()

        await opening.release.open()
        await openingLoad.value
        let scrollView = makeCanvas(for: viewModel)
        let fit = try #require(ERDiagramLoadFixture.exactFit(of: scrollView))
        #expect(fit < 1)
        #expect(abs(scrollView.magnification - fit) < 0.001)

        viewModel.viewport.resetZoom()
        viewModel.viewport.zoomOut()
        await returning.release.open()
        await returningLoad.value

        #expect(scrollView.magnification == 0.75)
        #expect(fixture.driver.catalogReadCount == 1)
        #expect(viewModel.loadState == .loaded)
    }

    @Test("A load that failed can be tried again")
    func failedLoadCanBeRetried() async {
        let fixture = ERDiagramLoadFixture(failingReads: 1)
        defer { fixture.tearDown() }

        await fixture.viewModel.loadDiagram()
        #expect(hasFailed(fixture.viewModel.loadState))

        await fixture.viewModel.loadDiagram()
        #expect(fixture.viewModel.loadState == .loaded)
        #expect(fixture.driver.catalogReadCount == 2)
    }
}
