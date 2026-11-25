import Foundation
import WaltzCore

final class QuizTests {
    let db = try! GuideDatabase.bundled()
    func testDemiMarriageRightSideOptionsUseFocusedOCR() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let image = try! loadImage(root.appendingPathComponent("demi-marriage.png").path)
        let o = try! VisionReader(database: db).read(image)
        XCTAssertEqual(o.scene, .answers)
        XCTAssertEqual(o.character, "玛格达")
        XCTAssertEqual(o.lines.allSatisfy { $0.center.y < 0.79 }, true)
        XCTAssertEqual(o.buttons.map(\.text), ["破坏血统", "自由恋爱", "错在阶级", "修改法律"])
        XCTAssertEqual(db.answer(character: "黛咪", text: o.text, options: o.buttons.map(\.text))?.index, 2)
        var engine = Engine(database: db)
        let quiz = TextBox(text: "好感度问答", confidence: 1, rect: UnitRect(x: 0.1, y: 0.55, width: 0.2, height: 0.02))
        _ = engine.next(Observation(scene: .menu, character: "黛咪", hearts: 3, buttons: [quiz]))
        XCTAssertEqual(engine.next(o).point, o.buttons[2].center)
    }
    func testSingleKnownAnswerNeedsNeitherStemNorOriginalOrder() {
        XCTAssertEqual(db.answer(character: "露西莉亚", text: "", options: ["未知甲", "黑色", "未知乙", "未知丙"])?.index, 1)
        XCTAssertEqual(db.answer(character: "露西莉亚", text: "法律是什么", options: ["红色", "未知甲", "黑色", "未知乙"])?.index, 2)
    }
    func testBarisStructuralProblemAlias() {
        XCTAssertEqual(db.answer(character: "巴里斯", text: "", options: ["破坏了稳定", "对安全有利", "浪费税金", "结构问题"])?.index, 3)
        XCTAssertEqual(db.answer(character: "巴里斯", text: "", options: ["结构问题", "浪费税金", "破坏了稳定", "对安全有利"])?.index, 0)
    }
    func testAmbiguousAnswersNeedQuestionEvidence() {
        let data = #"{"source":"test","sha256":"test","characters":[{"name":"测试人物","aliases":[],"topics":[],"codes":[1]}],"questions":[{"name":"甲类问题","group":0,"answers":{"1":["甲答案"],"2":["乙答案"],"3":["丙答案"]}},{"name":"乙类问题","group":0,"answers":{"1":["乙答案"],"2":["甲答案"],"3":["丙答案"]}}]}"#.data(using: .utf8)!
        let custom = try! JSONDecoder().decode(GuideDatabase.self, from: data)
        XCTAssertNil(custom.answer(character: "测试人物", text: "", options: ["乙答案", "甲答案", "丙答案"]))
        XCTAssertEqual(custom.answer(character: "测试人物", text: "甲类问题", options: ["乙答案", "甲答案", "丙答案"])?.index, 1)
        XCTAssertNil(custom.answer(character: "测试人物", text: "甲类问题", options: ["甲答案", "甲答案", "丙答案"]))
    }
    func testUnknownAndPartialTextDoNotBecomeGuesses() {
        XCTAssertNil(db.answer(character: "巴里斯", text: "警备队扩张", options: ["破坏了稳定", "对安全有利", "浪费税金", "新的未知答案"]))
        XCTAssertNil(db.answer(character: "巴里斯", text: "", options: ["结构", "问题", "未知答案"]))
    }
    func testEntireGuideWithReorderedOptionsAndNoQuestion() {
        for person in db.characters {
            for q in db.questions {
                let options = q.answers.keys.compactMap(Int.init).sorted(by: >).compactMap { q.answers[String($0)]?.first }
                let expected = options.count - person.codes[q.group]
                XCTAssertEqual(db.answer(character: person.name, text: "", options: options)?.index, expected)
            }
        }
    }
    func testQuizCannotReuseIdentityWhenCurrentBadgeIsMissing() {
        var engine = Engine(database: db)
        let quiz = TextBox(text: "好感度问答", confidence: 1, rect: UnitRect(x: 0.08, y: 0.54, width: 0.25, height: 0.02))
        _ = engine.next(Observation(scene: .menu, character: "巴里斯", hearts: 3, buttons: [quiz]))
        let options = ["破坏了稳定", "对安全有利", "浪费税金", "结构问题"].enumerated().map { index, text in
            TextBox(text: text, confidence: 1, rect: UnitRect(x: 0.08, y: 0.42 + Double(index) * 0.08, width: 0.25, height: 0.02))
        }
        XCTAssertEqual(engine.next(Observation(scene: .answers, hearts: 3, buttons: options)).kind, .wait)
        XCTAssertEqual(engine.next(Observation(scene: .answers, character: "巴里斯", hearts: 3, buttons: options)).point, options[3].center)
    }
    func testMargdaKeepsQuizTargetButNewNPCStops() {
        var engine = Engine(database: db)
        let quiz = TextBox(text: "好感度问答", confidence: 1, rect: UnitRect(x: 0.08, y: 0.54, width: 0.25, height: 0.02))
        _ = engine.next(Observation(scene: .menu, character: "巴里斯", hearts: 3, buttons: [quiz]))
        let options = ["破坏了稳定", "对安全有利", "浪费税金", "结构问题"].enumerated().map { i, text in
            TextBox(text: text, confidence: 1, rect: UnitRect(x: 0.75, y: 0.42 + Double(i) * 0.08, width: 0.2, height: 0.02))
        }
        XCTAssertEqual(engine.next(Observation(scene: .answers, character: "玛格达", hearts: 0, buttons: options)).point, options[3].center)
        XCTAssertEqual(engine.lockedCharacter, "巴里斯")
        XCTAssertEqual(engine.next(Observation(scene: .answers, character: "修伊", buttons: options)).kind, .pause)
        var fresh = Engine(database: db)
        XCTAssertEqual(fresh.next(Observation(scene: .answers, character: "玛格达", hearts: 0, buttons: options)).kind, .wait)
    }
    func testCanResumeVisibleQuizForVerifiedFullHeartCharacter() {
        let options = ["破坏了稳定", "对安全有利", "浪费税金", "结构问题"].enumerated().map { index, text in
            TextBox(text: text, confidence: 1, rect: UnitRect(x: 0.08, y: 0.42 + Double(index) * 0.08, width: 0.25, height: 0.02))
        }
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(Observation(scene: .answers, character: "巴里斯", hearts: 3, buttons: options)).point, options[3].center)
        var noBadge = Engine(database: db)
        XCTAssertEqual(noBadge.next(Observation(scene: .answers, hearts: 3, buttons: options)).kind, .wait)
        var uncertain = Engine(database: db)
        XCTAssertEqual(uncertain.next(Observation(scene: .answers, character: "巴里斯", buttons: options)).kind, .wait)
    }
}
