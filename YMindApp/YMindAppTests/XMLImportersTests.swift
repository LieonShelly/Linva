import Testing
import Foundation
@testable import YMindApp

@Suite("OPMLImporter")
struct OPMLImporterTests {
    private func parse(_ xml: String) throws -> MindMapDocument {
        try OPMLImporter().parse(Data(xml.utf8))
    }

    @Test func outlineNesting_buildsTree() throws {
        let xml = """
        <?xml version="1.0"?>
        <opml version="1.0"><body>
          <outline text="root">
            <outline text="child"><outline text="grandchild"/></outline>
          </outline>
        </body></opml>
        """
        let doc = try parse(xml)
        #expect(doc.root.text == "root")
        #expect(doc.root.children[0].text == "child")
        #expect(doc.root.children[0].children[0].text == "grandchild")
    }

    @Test func emptyText_becomesUnnamed() throws {
        let xml = """
        <opml><body><outline text="root"><outline/></outline></body></opml>
        """
        let doc = try parse(xml)
        #expect(doc.root.children[0].text == "未命名")
    }

    @Test func noteAttribute_ignored() throws {
        let xml = """
        <opml><body><outline text="root"><outline text="a" _note="备忘"/></outline></body></opml>
        """
        let doc = try parse(xml)
        #expect(doc.root.children[0].text == "a")
    }

    @Test func invalidXML_throws() {
        #expect(throws: ImportError.invalidXML) {
            _ = try parse("<opml><body></broken")
        }
    }

    @Test func emptyBody_noOutline_throwsInvalidXML() {
        #expect(throws: ImportError.invalidXML) {
            _ = try parse("<opml><body/></opml>")
        }
    }

    @Test func rootChildren_getAlternatingSide() throws {
        let xml = """
        <opml><body><outline text="root"><outline text="a"/><outline text="b"/><outline text="c"/></outline></body></opml>
        """
        let doc = try parse(xml)
        #expect(doc.root.children.map(\.side) == [.left, .right, .left])
    }
}

@Suite("FreeMindImporter")
struct FreeMindImporterTests {
    private func parse(_ xml: String) throws -> MindMapDocument {
        try FreeMindImporter().parse(Data(xml.utf8))
    }

    @Test func nodeNesting_buildsTree() throws {
        let xml = """
        <map version="1.0.1">
          <node TEXT="root"><node TEXT="child"><node TEXT="grandchild"/></node></node>
        </map>
        """
        let doc = try parse(xml)
        #expect(doc.root.text == "root")
        #expect(doc.root.children[0].text == "child")
        #expect(doc.root.children[0].children[0].text == "grandchild")
    }

    @Test func emptyTEXT_becomesUnnamed() throws {
        let xml = "<map><node TEXT=\"root\"><node/></node></map>"
        let doc = try parse(xml)
        #expect(doc.root.children[0].text == "未命名")
    }

    @Test func coordinateAttributes_ignored() throws {
        let xml = """
        <map><node TEXT="root"><node TEXT="a" POSITION="right" ID="n1"/></node></map>
        """
        let doc = try parse(xml)
        #expect(doc.root.children[0].text == "a")
    }

    @Test func rootChildren_getAlternatingSide() throws {
        let xml = """
        <map><node TEXT="root"><node TEXT="a"/><node TEXT="b"/><node TEXT="c"/></node></map>
        """
        let doc = try parse(xml)
        #expect(doc.root.children.map(\.side) == [.left, .right, .left])
    }

    @Test func emptyMap_noNode_throwsInvalidXML() {
        #expect(throws: ImportError.invalidXML) {
            _ = try parse("<map/>")
        }
    }
}