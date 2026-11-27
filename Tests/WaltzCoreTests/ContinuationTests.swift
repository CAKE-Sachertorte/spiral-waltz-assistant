import Foundation
import WaltzCore

final class ContinuationTests {
    let db = try! GuideDatabase.bundled()
    func testAttachedScreens() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        for i in 0..<4 {
            let image = try! loadImage(root.appendingPathComponent("continuation-\(i).png").path)
            let o = try! VisionReader(database: db).read(image, preferOptions: false)
            var engine = Engine(database: db)
            let decision = engine.next(o)
            XCTAssertEqual(decision.kind, i < 2 ? .tap : .done)
            if i == 0 { XCTAssertEqual(decision.kind, .tap) }
            if i == 1 {
                XCTAssertEqual(o.scene, .eavesdrop)
                XCTAssertEqual(decision.point.map { $0.x > 0.7 && $0.y > 0.6 }, true)
            }
        }
    }
    func testStandaloneRewardAndDialogue() {
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(Observation(scene: .reward)).point, Engine.center)
        XCTAssertEqual(engine.next(Observation(scene: .dialogue, text: "哈哈，您太客气了啦")).point, Engine.center)
        XCTAssertEqual(engine.lockedCharacter, nil)
        XCTAssertEqual(engine.next(Observation(scene: .unknown)).kind, .wait)
        XCTAssertEqual(engine.next(Observation(scene: .blocked)).kind, .pause)
    }
    func testNoEavesdropWithoutRememberedCharacter() {
        let labels = ["跟上去", "不偷听", "任务信息"].enumerated().map { i, text in
            TextBox(text: text, confidence: 1, rect: UnitRect(x: i == 2 ? 0.5 : 0.73, y: i == 2 ? 0.07 : 0.57 + Double(i) * 0.08, width: 0.24, height: 0.025))
        }
        let o = SceneClassifier(database: db).classify(lines: labels, heartScores: [0,0,0], skip: false)
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(o).point, labels[1].center)
    }
    func testBothExhaustionMessagesStopWithoutRequiringAPhase() {
        for text in ["基本上都和大家见过了，再逛下去似乎只能碰运气偷听点消息了呢。", "如果想要和人聊天的话，似乎还是直接找他们比较快。"] {
            var engine = Engine(database: db)
            XCTAssertEqual(engine.next(Observation(scene: .dialogue, text: text)).kind, .done)
        }
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(Observation(scene: .dialogue, text: "今天真想碰运气")).kind, .tap)
    }
}
