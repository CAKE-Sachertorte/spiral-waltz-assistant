import Foundation
import CoreGraphics
import WaltzCore

final class Nov26Tests {
    let db = try! GuideDatabase.bundled()
    func read(_ index: Int, preferOptions: Bool = false) -> Observation {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try! VisionReader(database: db).read(loadImage(root.appendingPathComponent("nov26-\(index).png").path), preferOptions: preferOptions)
    }
    func button(_ text: String, y: Double = 0.5) -> TextBox {
        TextBox(text: text, confidence: 1, rect: UnitRect(x: 0.1, y: y, width: 0.2, height: 0.03))
    }
    func testBadgeSpellingAndAttachedMenus() {
        XCTAssertEqual(db.character(named: "玛菲利娅·赫尔")?.name, "玛菲利亚·赫尔")
        XCTAssertEqual(db.character(named: "玛菲利娅")?.name, "玛菲利亚·赫尔")
        XCTAssertNil(db.character(named: "刚才和玛菲利娅聊过天"))
        let native = read(1)
        XCTAssertEqual(native.character, "玛菲利亚·赫尔")
        XCTAssertEqual(native.hearts, 3)
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(native).kind, .tapAndSkip)
        let phone = read(6)
        XCTAssertEqual(phone.character, "冈萨洛")
        XCTAssertEqual(phone.hearts, 1)
        var phoneEngine = Engine(database: db)
        XCTAssertEqual(phoneEngine.next(phone).point, phone.buttons.first { normalize($0.text) == "和他聊聊" }?.center)
    }
    func testAttachedAnswerVariantsAcrossBothSources() {
        for (index, person) in [(2, "吉当"), (8, "琉"), (9, "妮柯斯")] {
            for focused in [false, true] {
                let o = read(index, preferOptions: focused)
                XCTAssertEqual(o.scene, .answers)
                XCTAssertEqual(o.character, "玛格达")
                XCTAssertEqual(db.answer(character: person, text: o.text, options: o.buttons.map(\.text))?.index, 2)
                var engine = Engine(database: db)
                _ = engine.next(Observation(scene: .menu, character: person, hearts: 3, buttons: [button("好感度问答")]))
                XCTAssertEqual(engine.next(o).point, o.buttons.dropFirst(2).first?.center)
            }
        }
        XCTAssertNil(db.answer(character: "妮柯斯", text: "魔法", options: ["防御结界", "治疗魔法", "新的魔法", "火球术"]))
    }
    func testCompetitionAfterResultContinuesWithoutASkip() {
        for index in [3, 4] {
            let o = read(index)
            XCTAssertEqual(o.scene, .danceScene)
            var fresh = Engine(database: db)
            XCTAssertEqual(fresh.next(o).point, Engine.center)
            XCTAssertEqual(fresh.next(o).point, Engine.center)
        }
        let classifier = SceneClassifier(database: db)
        for label in ["胜利", "失败"] {
            let result = TextBox(text: label, confidence: 1, rect: UnitRect(x: 0.3, y: 0.4, width: 0.4, height: 0.08))
            let o = classifier.classify(lines: [result], heartScores: [], skip: false)
            XCTAssertEqual(o.scene, .reward)
            var engine = Engine(database: db)
            XCTAssertEqual(engine.next(o).point, Engine.center)
            XCTAssertEqual(engine.next(Observation(scene: .unknown)).point, Engine.center)
        }
    }
    func testPassiveCompetitionKeepsWanderingAndIgnoresOpponentIdentity() {
        var engine = Engine(database: db)
        engine.autoSwitch = true
        _ = engine.next(Observation(scene: .menu, character: "马修", hearts: 3, buttons: [button("一会儿再见")]))
        let contest = read(5)
        XCTAssertEqual(contest.scene, .danceScene)
        let action = engine.next(contest)
        XCTAssertEqual(action.kind, .tap)
        XCTAssertEqual(action.point.map { $0.x > 0.75 && $0.y > 0.8 }, true)
        XCTAssertEqual(engine.lockedCharacter, "马修")
        XCTAssertEqual(engine.next(Observation(scene: .unknown)).point, Engine.center)
        for _ in 0..<3 { XCTAssertEqual(engine.next(Observation(scene: .reward)).point, Engine.center) }
        _ = engine.next(Observation(scene: .hub, buttons: [button("闲逛")]))
        _ = engine.next(Observation(scene: .menu, character: "冈萨洛", hearts: 1, buttons: [button("和他聊聊")]))
        XCTAssertEqual(engine.lockedCharacter, "冈萨洛")
        var fresh = Engine(database: db)
        XCTAssertEqual(fresh.next(contest).kind, .tap)
        XCTAssertEqual(fresh.lockedCharacter, nil)
        var unknown = Engine(database: db)
        XCTAssertEqual(unknown.next(Observation(scene: .unknown)).kind, .wait)
        XCTAssertEqual(engine.next(Observation(scene: .blocked, text: "商城")).kind, .pause)
    }
    func testIntelligenceScreenshotStillContinues() {
        let o = read(7)
        XCTAssertEqual(o.scene, .reward)
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(o).point, Engine.center)
    }
}
