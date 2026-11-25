import Foundation
import WaltzCore

final class EngineTests {
    let db = try! GuideDatabase.bundled()
    func button(_ text: String, _ y: Double = 0.6, _ x: Double = 0.2) -> TextBox {
        TextBox(text: text, confidence: 0.99, rect: UnitRect(x: x - 0.12, y: y - 0.015, width: 0.24, height: 0.03))
    }
    func menu(_ person: String = "阿伦", hearts: Int? = 1, extra: [TextBox] = []) -> Observation {
        Observation(scene: .menu, character: person, hearts: hearts, buttons: [button("和他聊聊"), button("一会儿再见", 0.72)] + extra)
    }
    func testChatUsesPreferenceAndFixedSkipAndStopsAtFull() {
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(menu()).kind, .tap)
        let topics = Observation(scene: .topics, character: "阿伦", buttons: [button("返回", 0.45), button("商业", 0.52), button("风物", 0.66)])
        let action = engine.next(topics)
        XCTAssertEqual(action.kind, .tapAndSkip)
        XCTAssertEqual(action.point, button("风物", 0.66).center)
        XCTAssertEqual(action.skipPoint, Engine.skipPoint)
        XCTAssertEqual(engine.next(menu(hearts: 3)).kind, .done)
    }
    func testIntelligenceThenQuizThenDone() {
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(menu("露西莉亚", hearts: 3, extra: [button("打听情报", 0.5)])).kind, .tapAndSkip)
        XCTAssertEqual(engine.next(Observation(scene: .reward, text: "获得情报 点击屏幕继续")).point, Engine.center)
        XCTAssertEqual(engine.next(menu("露西莉亚", hearts: 3, extra: [button("好感度问答", 0.5)])).kind, .tap)
        let answers = ["黑色", "蓝色", "绿色", "红色"].enumerated().map { button($0.element, 0.44 + Double($0.offset) * 0.08) }
        let action = engine.next(Observation(scene: .answers, character: "露西莉亚", buttons: answers, text: "玛格达最喜欢的颜色是？"))
        XCTAssertEqual(action.point, answers[0].center)
        XCTAssertEqual(action.kind, .tap)
        XCTAssertEqual(engine.next(menu("露西莉亚", hearts: 3)).kind, .done)
    }
    func testOptionalDanceAfterCoreTasks() {
        var engine = Engine(database: db)
        let action = engine.next(menu("吉当", hearts: 3, extra: [button("神秘商店"), button("跳舞", 0.5), button("跳过", 0.5, 0.55), button("主动比美", 0.65)]))
        XCTAssertEqual(action.kind, .tap)
        XCTAssertEqual(action.point, button("跳过", 0.5, 0.55).center)
    }
    func testUnknownHeartsWaitAndChangedCharacterPauses() {
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(menu(hearts: nil)).kind, .wait)
        _ = engine.next(menu())
        XCTAssertEqual(engine.next(menu("吉当")).kind, .pause)
    }
    func testMissingBadgeCannotReusePreviousCharactersGuide() {
        var engine = Engine(database: db)
        _ = engine.next(menu())
        XCTAssertEqual(engine.next(Observation(scene: .menu, hearts: 1, buttons: [button("和他聊聊")])).kind, .wait)
        XCTAssertEqual(engine.next(Observation(scene: .menu, hearts: 3, buttons: [button("打听情报")])).kind, .wait)
    }
    func testNoPreferredTopicReturnsWithoutWastingChat() {
        var engine = Engine(database: db)
        _ = engine.next(menu())
        let back = button("返回", 0.4)
        let action = engine.next(Observation(scene: .topics, character: "阿伦", buttons: [back, button("商业"), button("艺术"), button("政治")]))
        XCTAssertEqual(action.kind, .tap)
        XCTAssertEqual(action.point, back.center)
    }
    func testUnknownQuestionPausesRatherThanGuessing() {
        var engine = Engine(database: db)
        _ = engine.next(menu("凌格兰", hearts: 3, extra: [button("好感度问答")]))
        let action = engine.next(Observation(scene: .answers, character: "凌格兰", buttons: [button("左边"), button("右边"), button("不知道")], text: "新的未知事件"))
        XCTAssertEqual(action.kind, .pause)
    }
    func testLawAndMoneyAndColorUseDifferentGroups() {
        XCTAssertEqual(db.answer(character: "凌格兰", text: "法律是什么", options: ["秩序的保证", "统治的工具", "人性的束缚"])?.index, 1)
        XCTAssertEqual(db.answer(character: "雷斯林", text: "用不完的金币", options: ["帮助穷人", "控制金融", "报复"])?.index, 1)
        XCTAssertEqual(db.answer(character: "尤文", text: "喜欢的颜色", options: ["黑色", "蓝色", "绿色", "红色"])?.index, 2)
    }
    func testOptionFingerprintRecognizesQuestionWithoutIntro() {
        XCTAssertEqual(db.answer(character: "露西莉亚", text: "", options: ["黑色", "蓝色", "绿色", "红色"])?.index, 0)
        XCTAssertNil(db.answer(character: "不认识的人", text: "颜色", options: ["黑色", "蓝色", "绿色", "红色"]))
    }
    func testCharacterAliasesAndShortNameDoNotMatchArbitraryDialogue() {
        XCTAssertEqual(db.character(named: "雷斯林·巴伐伦卡")?.name, "雷斯林")
        XCTAssertEqual(db.character(named: "露西利亚")?.name, "露西莉亚")
        XCTAssertNil(db.character(named: "我刚刚看到了琉的衣服"))
    }
}
