import Foundation
import WaltzCore
final class MenuRecoveryTests {
    let db = try! GuideDatabase.bundled()
    func read(_ i: Int, focused: Bool = false) -> Observation {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("nov26b-\(i).png").path),preferOptions:focused)
    }
    func button(_ text: String, _ y: Double = 0.6) -> TextBox {
        TextBox(text:text,confidence:1,rect:UnitRect(x:0.08,y:y,width:0.27,height:0.03))
    }
    func testKalosMenuIsRecoveredInsteadOfAdvancingDialogue() {
        let o=read(1)
        XCTAssertEqual(o.scene,.menu)
        XCTAssertEqual(o.character,"卡洛斯")
        XCTAssertEqual(o.buttons.contains{normalize($0.text)=="一会儿再见"},true)
        var engine=Engine(database:db);engine.autoSwitch=true
        let a=engine.next(o)
        XCTAssertEqual(a.kind,.tap)
        XCTAssertEqual(a.point,o.buttons.first{normalize($0.text)=="一会儿再见"}?.center)
    }
    func testRewardUsesContinueHintAndAllowsAnimationRetries() {
        let o=read(2)
        XCTAssertEqual(o.scene,.reward)
        let hint=o.lines.first{normalize($0.text).contains("点击屏幕继")}
        XCTAssertEqual(hint != nil,true)
        var engine=Engine(database:db)
        let a=engine.next(o)
        XCTAssertEqual(a.point,hint?.center)
        XCTAssertEqual(a.maximumIdenticalTaps,6)
        XCTAssertEqual(engine.next(Observation(scene:.dialogue)).maximumIdenticalTaps,2)
    }
    func testHamiltonAdventureIsReread() {
        let o=read(3)
        XCTAssertEqual(o.scene,.topics)
        XCTAssertEqual(o.buttons.contains{normalize($0.text)=="冒险"},true)
        var engine=Engine(database:db)
        _=engine.next(Observation(scene:.menu,character:"汉密尔顿",hearts:2,buttons:[button("和他聊聊")]))
        let action=engine.next(o)
        XCTAssertEqual(action.kind,.tapAndSkip)
        XCTAssertEqual(action.point,o.buttons.first{normalize($0.text)=="冒险"}?.center)
    }
    func testDecliningCharactersLeaveWithoutAChatGuide() {
        let o=read(4)
        XCTAssertEqual(o.scene,.menu)
        XCTAssertEqual(o.character,"琳娜")
        var engine=Engine(database:db);engine.autoSwitch=true
        let a=engine.next(o)
        XCTAssertEqual(a.kind,.tap)
        XCTAssertEqual(a.point,o.buttons.first{normalize($0.text)=="一会儿再见"}?.center)
        let bye=button("一会儿再见",0.7)
        let name=TextBox(text:"劳伦斯·乔卡瑟尔",confidence:1,rect:UnitRect(x:0.62,y:0.72,width:0.35,height:0.025))
        let raw=SceneClassifier(database:db).classify(lines:[name,bye,button("和他聊聊")],heartScores:[0,0,0],skip:false)
        XCTAssertEqual(raw.character,"劳伦斯")
        XCTAssertEqual(engine.next(raw).point,bye.center)
        XCTAssertEqual(engine.lockedCharacter,nil)
        var missing=Engine(database:db)
        XCTAssertEqual(missing.next(Observation(scene:.menu,character:"琳娜",hearts:0)).kind,.wait)
        XCTAssertNil(db.character(named:"琳娜"))
    }
    func testIvanBirdIsReadBeforeAnswering() {
        for focused in [false,true] {
            let o=read(5,focused:focused)
            XCTAssertEqual(o.buttons.map(\.text),["狗","鸟","猫","马"])
            var engine=Engine(database:db)
            _=engine.next(Observation(scene:.menu,character:"伊万",hearts:3,buttons:[button("好感度问答")]))
            let a=engine.next(o)
            XCTAssertEqual(a.kind,.tap)
            XCTAssertEqual(a.point,o.buttons.dropFirst().first?.center)
        }
        XCTAssertNil(db.answer(character:"伊万",text:"动物",options:["狗","猫","马"]))
    }
}
