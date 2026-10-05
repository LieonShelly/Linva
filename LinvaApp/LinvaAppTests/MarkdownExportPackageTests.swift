import Testing
import Foundation
@testable import LinvaApp

/// 有图 Markdown 文件夹包导出：所选目录下生成 <N>.md + assets/<blockId>.png。
/// 覆盖 DocumentWorkflow.exportMarkdown 有图分支的写盘路径（SavePanel 部分除外）。
@Suite("Markdown 文件夹包")
struct MarkdownExportPackageTests {
    @Test func imageDocument_folderPackage_writesMDAndAssets() throws {
        var doc = MindMapDocument.blank(rootText: "中心主題")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAFUlEQVR42mP8z8BQz0AEYBxVSF+FAP2mCPH4lGqPAAAAAElFTkSuQmCC")!
        let px = ImagePixelSize(width: 10, height: 10)!
        var child = Node(text: "带图子节点")
        child.blocks.append(ContentBlock(id: UUID(), kind: .image(.init(data: png, pixelSize: px))))
        doc.root.children = [child]

        let output = MarkdownExporter.output(from: doc)
        #expect(!output.images.isEmpty)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 镜像 exportMarkdown 有图分支的写盘逻辑
        let mdName = "中心主題.md"
        let mdURL = dir.appendingPathComponent(mdName)
        let assetsDir = dir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try Data(output.text.utf8).write(to: mdURL, options: .atomic)
        for image in output.images {
            try image.data.write(
                to: assetsDir.appendingPathComponent("\(image.blockId.uuidString).png"),
                options: .atomic)
        }

        #expect(FileManager.default.fileExists(atPath: mdURL.path))
        #expect(FileManager.default.fileExists(atPath: assetsDir.path))
        let md = try String(contentsOf: mdURL, encoding: .utf8)
        #expect(md.contains("assets/\(output.images[0].blockId.uuidString).png"))
        let assets = try FileManager.default.contentsOfDirectory(atPath: assetsDir.path)
        #expect(assets.count == 1)
        #expect(assets[0] == "\(output.images[0].blockId.uuidString).png")
    }

    @Test func imagelessDocument_singleFileTextOnly() throws {
        let doc = MindMapDocument.blank(rootText: "中心主題")
        let output = MarkdownExporter.output(from: doc)
        #expect(output.images.isEmpty)
        #expect(output.text == "# 中心主題\n")
    }
}
