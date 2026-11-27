import Foundation
import WaltzCore
final class Nov27Tests {
    let db = try! GuideDatabase.bundled()
    func read(_ i: Int, focused: Bool = false) -> Observation {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("nov27-\(i).png").path),preferOptions:focused)
    }
    func box(_ text: String, _ x: Double, _ y: Double, _ h: Double = 0.025) -> TextBox {
        TextBox(text:text,confidence:1,rect:UnitRect(x:x,y:y,width:0.2,height:h))
    }
    func testBallEndUsesHeadingsInsteadOfVariableMissions() {
        let o=read(4)
        XCTAssertEqual(o.scene,.finished)
        var e=Engine(database:db);e.autoSwitch=true
        XCTAssertEqual(e.next(o).kind,.done)
        let headings=[box("完成进度",0.55,0.15,0.06),box("获得奖励",0.55,0.60,0.06),box("行动目标",0.7,0.4),box("任意变化的任务",0.5,0.3)]
        let c=SceneClassifier(database:db)
        XCTAssertEqual(c.classify(lines:headings,heartScores:[],skip:false).scene,.finished)
        XCTAssertEqual(c.classify(lines:[box("完成进度",0.1,0.8),box("获得奖励",0.1,0.84)],heartScores:[],skip:false).scene == .finished,false)
    }
    func testLinnaBeautyBeforeGoodbyeWithoutChattingOrReplacingNpc() {
        let o=read(9),beauty=o.buttons.first{normalize($0.text)=="主动比美"},bye=o.buttons.first{normalize($0.text)=="一会儿再见"}
        var e=Engine(database:db);e.autoSwitch=true
        let a=e.next(o)
        XCTAssertEqual(a.kind,.tap)
        XCTAssertEqual(a.point,beauty?.center)
        XCTAssertEqual(e.competitionActive,true)
        _=e.next(Observation(scene:.danceScene))
        _=e.next(Observation(scene:.reward,text:"胜利"))
        XCTAssertEqual(e.next(o).point,bye?.center)
        XCTAssertEqual(e.lockedCharacter,nil)
        XCTAssertEqual(e.next(read(10)).point,read(10).buttons.first{normalize($0.text)=="一会儿再见"}?.center)
        XCTAssertEqual(e.next(read(7)).message.contains("不接受聊天"),true)
        // A new encounter with the same NPC can offer beauty again.
        let wander=box("闲逛",0.75,0.5)
        _=e.next(Observation(scene:.hub,buttons:[wander]))
        XCTAssertEqual(e.next(o).point,beauty?.center)
    }
    func testComplexCostumeStillFindsActualSkipAndBadge() {
        let contest=read(11)
        XCTAssertEqual(contest.scene,.danceScene)
        let skip=contest.lines.first{normalize($0.text)=="跳过" && $0.center.x>0.7 && $0.center.y>0.7}
        XCTAssertEqual(skip != nil,true)
        var e=Engine(database:db)
        XCTAssertEqual(e.next(contest).point,skip?.center)
        XCTAssertEqual(read(12).character,"白星")
        XCTAssertEqual(read(13).character,"白星")
    }
    func testPartialHubAlsoResetsLinnaEncounter() {
        let bye=box("一会儿再见",0.1,0.7),beauty=box("主动比美",0.1,0.55),wander=box("闲逛",0.75,0.5)
        let linna=Observation(scene:.menu,character:"琳娜",hearts:1,buttons:[beauty,bye])
        var e=Engine(database:db);e.autoSwitch=true
        _=e.next(Observation(scene:.menu,character:"卡洛斯",hearts:3,buttons:[bye]))
        _=e.next(linna);_=e.next(linna)
        XCTAssertEqual(e.next(Observation(scene:.blocked,lines:[wander])).point,wander.center)
        XCTAssertEqual(e.next(linna).point,beauty.center)
    }
    func testRandallMagicRereadsMisrecognizedHealing() {
        let o=read(14,focused:true)
        XCTAssertEqual(o.buttons.map(\.text),["防御结界","治疗魔法","隐身魔法","火球术"])
        var e=Engine(database:db)
        _=e.next(Observation(scene:.menu,character:"兰达尔",hearts:3,buttons:[box("好感度问答",0.1,0.5)]))
        let a=e.next(o)
        XCTAssertEqual(a.kind,.tap)
        XCTAssertEqual(a.point,o.buttons.dropFirst().first?.center)
    }
    func testOtherAttachedScreensUseRecognizedControls() {
        let reward=read(1)
        var e=Engine(database:db)
        XCTAssertEqual(reward.scene,.reward)
        XCTAssertEqual(e.next(reward).point?.y ?? 0 > 0.60,true)
        let money=read(2)
        XCTAssertEqual(money.buttons.map(\.text),["帮助穷人","控制金融","报复"])
        let pets=read(3)
        XCTAssertEqual(pets.buttons.map(\.text),["狗","鸟","猫","马"])
        XCTAssertEqual(db.answer(character:"黑手套",text:pets.text,options:pets.buttons.map(\.text))?.index,1)
        for i in [5,6] { XCTAssertEqual(read(i).scene,.menu) }
        let duchess=read(8)
        XCTAssertEqual(duchess.character,"克里斯蒂公爵夫人")
        XCTAssertEqual(e.next(duchess).kind,.tap)
        XCTAssertEqual(e.next(duchess).point,duchess.buttons.first{normalize($0.text)=="和他聊聊"}?.center)
        XCTAssertEqual(read(7).character,"劳伦斯")
    }
}
