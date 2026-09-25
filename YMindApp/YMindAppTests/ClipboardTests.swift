import Foundation
import Testing
@testable import YMindApp

@Suite("Clipboard")
struct ClipboardTests {
    @Test func cut_thenCancel_leavesTreeUntouched() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        session.selectOnly(a)

        session.cutSelection()
        #expect(session.cutSourceIds == [a])
        #expect(session.model.node(id: a) != nil)

        session.cancelCut()
        #expect(session.clipboard == nil)
        #expect(session.cutSourceIds.isEmpty)
        #expect(session.model.node(id: a) != nil)
    }

    @Test func copy_thenTwoPastes_eachIndependent() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let t1 = session.model.insertChild(parentId: root, text: "T1", side: .left, at: nil)
        let t2 = session.model.insertChild(parentId: root, text: "T2", side: .left, at: nil)
        session.selectOnly(a)
        session.copySelection()
        session.selectOnly(t1)
        session.pasteToPrimary()
        session.selectOnly(t2)
        session.pasteToPrimary()

        #expect(session.model.node(id: t1)?.children.count == 1)
        #expect(session.model.node(id: t2)?.children.count == 1)
        #expect(session.model.node(id: t1)?.children[0].id
            != session.model.node(id: t2)?.children[0].id)
        #expect(session.model.node(id: a) != nil)
    }

    @Test func pasteToOwnDescendant_isNoOp_forCut() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let g = session.model.insertChild(parentId: a, text: "G", side: nil, at: nil)
        session.selectOnly(a)
        session.cutSelection()
        session.selectOnly(g)
        session.pasteToPrimary()

        #expect(session.model.node(id: a) != nil)
        #expect(session.model.parentId(of: a) == root)  // 未搬
        #expect(session.cutSourceIds == [a])                          // 剪切态未清
    }
}
