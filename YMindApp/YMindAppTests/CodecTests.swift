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
        #expect(doc.version == 7)
        #expect(doc.root.fill == nil)
        #expect(doc.root.children[0].fill == nil)
    }

    @Test func unknownFillToken_decodesAsNil() throws {
        let json = """
        {"version":2,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"fill":"neon","children":[]}}
        """.data(using: .utf8)!
        let doc = try YMindCodec.decode(json)
        #expect(doc.version == 7)
        #expect(doc.root.fill == nil)
    }

    @Test func layoutRoundTrip_preservesLogicAndRadial() throws {
        var logic = MindMapDocument.blank(rootText: "根")
        logic.layout = .logic
        let logicBack = try YMindCodec.decode(try YMindCodec.encode(logic))
        #expect(logicBack.layout == .logic)

        let radial = MindMapDocument.blank(rootText: "根")
        let radialBack = try YMindCodec.decode(try YMindCodec.encode(radial))
        #expect(radialBack.layout == .radial)
    }

    @Test func v4FileWithoutLayout_decodesAsRadial() throws {
        let json = """
        {"version":4,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"children":[]}}
        """.data(using: .utf8)!
        let back = try YMindCodec.decode(json)
        #expect(back.version == 7)
        #expect(back.layout == .radial)
    }

    @Test func v5CollapsedRoot_migratesToBothSideFlags() throws {
        // v5 老文件：根 collapsed=true（左右全折）→ v6 迁为两侧独立 true，清遗留 collapsed。
        let json = """
        {"version":5,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":true,"children":[{"id":"00000000-0000-0000-0000-000000000002","text":"左","collapsed":false,"side":"left","children":[]}]}}
        """.data(using: .utf8)!
        let doc = try YMindCodec.decode(json)
        #expect(doc.version == 7)
        #expect(doc.root.collapsed == false)
        #expect(doc.root.collapsedLeft == true)
        #expect(doc.root.collapsedRight == true)
    }

    @Test func sanitize_clearsRootSideFlagsOnNonRoot() throws {
        // v6：非根节点的 collapsedLeft/Right 被消毒清 false（与 side 同层级约束）；根保留。
        let json = """
        {"version":6,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"collapsedLeft":true,"collapsedRight":true,"children":[{"id":"00000000-0000-0000-0000-000000000002","text":"子","collapsed":false,"collapsedLeft":true,"children":[]}]}}
        """.data(using: .utf8)!
        let doc = try YMindCodec.decode(json)
        #expect(doc.root.collapsed == false)
        #expect(doc.root.collapsedLeft == true)
        #expect(doc.root.collapsedRight == true)
        #expect(doc.root.children[0].collapsedLeft == false)
    }

    @Test func edgeStyleRoundTrip() throws {
        let doc = MindMapDocument.blank(rootText: "根")
        for style in EdgeStyle.allCases {
            var d = doc
            d.edgeStyle = style
            let data = try YMindCodec.encode(d)
            let back = try YMindCodec.decode(data)
            #expect(back.edgeStyle == style)
            #expect(back.version == MindMapDocument.currentVersion)
        }
    }

    @Test func edgeStyleDefaultsToElbow() throws {
        // 构造 v6 文档 JSON（无 edgeStyle 字段），decode 应缺省 .elbow
        let v6JSON = """
        {"version":6,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"children":[]}}
        """
        let doc = try YMindCodec.decode(Data(v6JSON.utf8))
        #expect(doc.edgeStyle == .elbow)
        #expect(doc.version == 7)
    }

    @Test func unknownEdgeStyleToken_decodesAsElbow() throws {
        // 未来文件：新版 app 新增的样式 token，旧 app 应零拒绝（同 fill 容错模式），
        // 而不是 decodeIfPresent(EdgeStyle.self) 因未知枚举值抛错。
        let futureJSON = """
        {"version":7,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"children":[]},"edgeStyle":"futureStyle"}
        """
        let doc = try YMindCodec.decode(Data(futureJSON.utf8))
        #expect(doc.edgeStyle == .elbow)
        #expect(doc.version == 7)
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
        #expect(back.version == 7)
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
        #expect(back.version == 7)
        #expect(back.root.image == nil)
    }

    @Test func v1File_chainMigrates() throws {
        let json = """
        {"version":1,"root":{"id":"\(UUID())","text":"v1","collapsed":false,"children":[]}}
        """
        let back = try YMindCodec.decode(Data(json.utf8))
        #expect(back.version == 7)
    }

    @Test func invalidImagePixelSize_decodesAsNil() throws {
        // 宽高非法（0/负）→ v3 解码容错为 nil（块合成时跳过图片块），不拒文件
        let json = """
        {"version":3,"root":{"id":"\(UUID())","text":"根","collapsed":false,"image":"iVBORw0KGgo=","imagePixelSize":{"width":0,"height":100},"children":[]}}
        """
        let back = try YMindCodec.decode(Data(json.utf8))
        #expect(back.version == 7)
        #expect(back.root.image == nil)
        #expect(back.root.text == "根")
    }

    @Test func v3FileWithImage_migratesToBlocks_imageAboveText() throws {
        // v3 格式：text + image + imagePixelSize，无 blocks。
        let json = """
        {"version":3,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"标题","collapsed":false,"image":"iVBORw0KGgo=","imagePixelSize":{"width":100,"height":50},"children":[]}}
        """.data(using: .utf8)!
        let back = try YMindCodec.decode(json)
        #expect(back.version == 7)
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
        #expect(back.version == 7)
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
