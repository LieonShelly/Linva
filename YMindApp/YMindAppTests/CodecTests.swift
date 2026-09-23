import Testing
import Foundation
@testable import YMindApp

@Suite("YMindCodec")
struct CodecTests {
    @Test func roundTrip() throws {
        let model = MindMapModel.makeNew()
        _ = model.insertChild(parentId: model.document.root.id, text: "左", side: .left, at: nil)
        model.document.root.children[0].collapsed = true
        let data = try YMindCodec.encode(model.document)
        let decoded = try YMindCodec.decode(data)
        #expect(decoded == model.document)
    }

    @Test func rejectsUnknownVersion() throws {
        let json = """
        {"version":99,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"x","collapsed":false,"children":[]}}
        """.data(using: .utf8)!
        #expect(throws: YMindCodecError.unsupportedVersion(99)) {
            _ = try YMindCodec.decode(json)
        }
    }

    @Test func stripsDeepSide() throws {
        let json = """
        {"version":1,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"side":"left","children":[{"id":"00000000-0000-0000-0000-000000000002","text":"一","collapsed":false,"side":"left","children":[{"id":"00000000-0000-0000-0000-000000000003","text":"二","collapsed":false,"side":"right","children":[]}]}]}}
        """.data(using: .utf8)!
        var warnings: [String]? = []
        let doc = try YMindCodec.decode(json, warnings: &warnings)
        #expect(doc.root.side == nil)
        #expect(doc.root.children[0].side == .left)
        #expect(doc.root.children[0].children[0].side == nil)
        #expect(warnings?.count == 1)
        #expect(warnings?.first?.contains("side") == true)
    }
}
