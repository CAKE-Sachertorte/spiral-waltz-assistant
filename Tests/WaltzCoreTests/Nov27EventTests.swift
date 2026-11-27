import Foundation
import WaltzCore
final class Nov27EventTests {
    let db=try! GuideDatabase.bundled()
    func read(_ i:Int)->Observation {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("nov27c-\(i).png").path),preferOptions:false)
    }
    func testEventStabilityIgnoresClockAndDialogueOcrButTracksChoices() {
        let first=read(2)
        XCTAssertEqual(first.scene,.eavesdrop)
        var second=first
        second.text="不同的对白与时钟 3:20"
        second.character=nil;second.hearts=2
        XCTAssertEqual(first.fingerprint,second.fingerprint)
        var e=Engine(database:db);e.autoSwitch=true
        let nav=TextBox(text:"闲逛",confidence:1,rect:UnitRect(x:0.75,y:0.5,width:0.2,height:0.03))
        _=e.next(Observation(scene:.hub,buttons:[nav]))
        XCTAssertEqual(e.next(second).point,second.buttons.sorted{$0.center.y<$1.center.y}.last?.center)
        second.buttons[0].text="新的上方选项"
        XCTAssertEqual(first.fingerprint == second.fingerprint,false)
    }
    func testArbitraryEventWordsChooseSecondDuringWanderingButNotQuiz() {
        let hero=TextBox(text:"玛格达",confidence:1,rect:UnitRect(x:0.1,y:0.7,width:0.2,height:0.02))
        let upper=TextBox(text:"凑近看看",confidence:1,rect:UnitRect(x:0.73,y:0.50,width:0.25,height:0.03))
        let lower=TextBox(text:"悄悄离开",confidence:1,rect:UnitRect(x:0.73,y:0.61,width:0.25,height:0.03))
        let o=SceneClassifier(database:db).classify(lines:[hero,lower,upper],heartScores:[],skip:false)
        XCTAssertEqual(o.scene,.eavesdrop)
        var e=Engine(database:db)
        XCTAssertEqual(e.next(o).point,lower.center)
        let start=TextBox(text:"好感度问答",confidence:1,rect:UnitRect(x:0.1,y:0.5,width:0.25,height:0.03))
        _=e.next(Observation(scene:.menu,character:"兰达尔",hearts:3,buttons:[start]))
        XCTAssertEqual(e.next(o).kind,.wait)
    }
    func testMenuStabilityIgnoresHudButTracksCharacterAndActions() {
        let chat=TextBox(text:"和他聊聊",confidence:1,rect:UnitRect(x:0.1,y:0.5,width:0.2,height:0.03))
        let first=Observation(scene:.menu,character:"冈萨洛",hearts:0,buttons:[chat],text:"时钟18:23 台词甲")
        var next=first;next.text="时钟18:22 台词乙"
        XCTAssertEqual(first.fingerprint,next.fingerprint)
        next.character=nil
        XCTAssertEqual(first.fingerprint == next.fingerprint,false)
        next=first;next.hearts=3
        XCTAssertEqual(first.fingerprint == next.fingerprint,false)
        next=first;next.buttons=[]
        XCTAssertEqual(first.fingerprint == next.fingerprint,false)
    }
    func testGonzaloBadgeAndRandallAnswerRemainRecognized() {
        let menu=read(3)
        XCTAssertEqual(menu.scene,.menu)
        XCTAssertEqual(menu.character,"冈萨洛")
        var e=Engine(database:db)
        XCTAssertEqual(e.next(menu).point,menu.buttons.first{normalize($0.text)=="和他聊聊"}?.center)
        let quiz=read(1)
        var q=Engine(database:db)
        let start=TextBox(text:"好感度问答",confidence:1,rect:UnitRect(x:0.1,y:0.5,width:0.25,height:0.03))
        _=q.next(Observation(scene:.menu,character:"兰达尔",hearts:3,buttons:[start]))
        XCTAssertEqual(q.next(quiz).point,quiz.buttons.dropFirst().first?.center)
    }
}
