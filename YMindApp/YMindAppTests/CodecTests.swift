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
        {"version":2,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"side":"left","children":[{"id":"00000000-0000-0000-0000-000000000002","text":"一","collapsed":false,"side":"left","children":[{"id":"00000000-0000-0000-0000-000000000003","text":"二","collapsed":false,"side":"right","children":[]}]}]}}
        """.data(using: .utf8)!
        var warnings: [String]? = []
        let doc = try YMindCodec.decode(json, warnings: &warnings)
        #expect(doc.root.side == nil)
        #expect(doc.root.children[0].side == .left)
        #expect(doc.root.children[0].children[0].side == nil)
        #expect(warnings?.count == 1)
        #expect(warnings?.first?.contains("side") == true)
    }

    @Test func roundTrip_preservesFill() throws {
        let model = MindMapModel.makeNew()
        model.document.root.fill = .sage
        let child = model.insertChild(parentId: model.document.root.id, text: "子", side: .left, at: nil)
        _ = model.mutate(id: child) { $0.fill = .rose }
        let data = try YMindCodec.encode(model.document)
        let decoded = try YMindCodec.decode(data)
        #expect(decoded == model.document)
        #expect(decoded.root.fill == .sage)
        #expect(decoded.root.children[0].fill == .rose)
    }

    @Test func migratesV1ToV2() throws {
        let json = """
        {"version":1,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"children":[{"id":"00000000-0000-0000-0000-000000000002","text":"子","collapsed":false,"children":[]}]}}
        """.data(using: .utf8)!
        let doc = try YMindCodec.decode(json)
        #expect(doc.version == 3)
        #expect(doc.root.fill == nil)
        #expect(doc.root.children[0].fill == nil)
    }

    @Test func unknownFillToken_decodesAsNil() throws {
        let json = """
        {"version":2,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"fill":"neon","children":[]}}
        """.data(using: .utf8)!
        let doc = try YMindCodec.decode(json)
        #expect(doc.version == 3)
        #expect(doc.root.fill == nil)
    }
}

@Suite("Codec v3 图片字段")
struct CodecImageTests {
    private func documentWithImage() -> MindMapDocument {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [
            Node(text: "带图", image: Data([0x89, 0x50]), imagePixelSize: ImagePixelSize(width: 1024, height: 512)),
            Node(text: "无图"),
        ]
        return doc
    }

    @Test func imageRoundTrip() throws {
        let data = try YMindCodec.encode(documentWithImage())
        let back = try YMindCodec.decode(data)
        #expect(back.version == 3)
        #expect(back.root.children[0].image == Data([0x89, 0x50]))
        #expect(back.root.children[0].imagePixelSize == ImagePixelSize(width: 1024, height: 512))
        #expect(back.root.children[1].image == nil)
    }

    @Test func v2FileWithoutImage_opensWithoutReject() throws {
        // v2 老文件：version=2、无 image 字段
        let json = """
        {"version":2,"root":{"id":"\(UUID())","text":"老文件","collapsed":false,"children":[]}}
        """
        let back = try YMindCodec.decode(Data(json.utf8))
        #expect(back.version == 3)
        #expect(back.root.image == nil)
    }

    @Test func v1File_chainMigrates() throws {
        let json = """
        {"version":1,"root":{"id":"\(UUID())","text":"v1","collapsed":false,"children":[]}}
        """
        let back = try YMindCodec.decode(Data(json.utf8))
        #expect(back.version == 3)
    }

    @Test func invalidImagePixelSize_decodesAsNil() throws {
        // 宽高非法（0/负）→ 解码容错为 nil，不拒文件
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.imagePixelSize = ImagePixelSize(width: 0, height: 100)
        let data = try JSONEncoder().encode(doc)
        let back = try YMindCodec.decode(data)
        #expect(back.root.imagePixelSize == nil)
    }
}
