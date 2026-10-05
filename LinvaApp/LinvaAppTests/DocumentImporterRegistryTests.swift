import Testing
import Foundation
@testable import LinvaApp

@Suite("DocumentImporterRegistry")
struct DocumentImporterRegistryTests {
    @Test func importer_routesMarkdown() {
        #expect(DocumentImporterRegistry.importer(for: "md") is MarkdownImporter)
        #expect(DocumentImporterRegistry.importer(for: "markdown") is MarkdownImporter)
        #expect(DocumentImporterRegistry.importer(for: "MD") is MarkdownImporter) // 大小写不敏感
    }
    @Test func importer_routesXMLFormats() {
        #expect(DocumentImporterRegistry.importer(for: "opml") is OPMLImporter)
        #expect(DocumentImporterRegistry.importer(for: "mm") is FreeMindImporter)
    }
    @Test func importer_unknownExtension_returnsNil() {
        #expect(DocumentImporterRegistry.importer(for: "xmind") == nil)
        #expect(DocumentImporterRegistry.importer(for: "txt") == nil)
    }
}