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
        #expect(doc.version == 4)
        #expect(doc.root.fill == nil)
        #expect(doc.root.children[0].fill == nil)
    }

    @Test func unknownFillToken_decodesAsNil() throws {
        let json = """
        {"version":2,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"fill":"neon","children":[]}}
        """.data(using: .utf8)!
        let doc = try YMindCodec.decode(json)
        #expect(doc.version == 4)
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
        #expect(back.version == 4)
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
        #expect(back.version == 4)
        #expect(back.root.image == nil)
    }

    @Test func v1File_chainMigrates() throws {
        let json = """
        {"version":1,"root":{"id":"\(UUID())","text":"v1","collapsed":false,"children":[]}}
        """
        let back = try YMindCodec.decode(Data(json.utf8))
        #expect(back.version == 4)
    }

    @Test func invalidImagePixelSize_decodesAsNil() throws {
        // 宽高非法（0/负）→ v3 解码容错为 nil（块合成时跳过图片块），不拒文件
        let json = """
        {"version":3,"root":{"id":"\(UUID())","text":"根","collapsed":false,"image":"iVBORw0KGgo=","imagePixelSize":{"width":0,"height":100},"children":[]}}
        """
        let back = try YMindCodec.decode(Data(json.utf8))
        #expect(back.version == 4)
        #expect(back.root.image == nil)
        #expect(back.root.text == "根")
    }

    @Test func v3FileWithImage_migratesToBlocks_imageAboveText() throws {
        // v3 格式：text + image + imagePixelSize，无 blocks。
        let json = """
        {"version":3,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"标题","collapsed":false,"image":"iVBORw0KGgo=","imagePixelSize":{"width":100,"height":50},"children":[]}}
        """.data(using: .utf8)!
        let back = try YMindCodec.decode(json)
        #expect(back.version == 4)
        let root = back.root
        #expect(root.blocks.count == 2)
        if case .image = root.blocks[0].kind {} else { Issue.record("第 0 块应为图片") }
        if case .text(let s) = root.blocks[1].kind { #expect(s == "标题") } else { Issue.record("第 1 块应为文本") }
        #expect(root.image == Data(base64Encoded: "iVBORw0KGgo="))
        #expect(root.text == "标题")
    }

    @Test func v4RoundTrip_blocksPreserved() throws {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        let blockId = model.appendImageBlock(
            id: root,
            image: Data([0x89, 0x50]),
            pixelSize: ImagePixelSize(width: 10, height: 20)!
        )
        let data = try YMindCodec.encode(model.document)
        let back = try YMindCodec.decode(data)
        #expect(back.version == 4)
        #expect(back.root.blocks.count == 2)
        #expect(back.root.blocks[1].id == blockId)
        if case .image(let img) = back.root.blocks[1].kind {
            #expect(img.data == Data([0x89, 0x50]))
            #expect(img.pixelSize == ImagePixelSize(width: 10, height: 20))
        } else {
            Issue.record("blocks[1] 应为图片")
        }
    }
}
