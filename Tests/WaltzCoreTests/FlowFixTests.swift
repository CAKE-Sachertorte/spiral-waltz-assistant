import Foundation
import WaltzCore
final class FlowFixTests {
 let db = try! GuideDatabase.bundled()
 func testTopicsSurviveMissingReturnLabel() {
  let lines=["冒险","神秘","娱乐"].enumerated().map { i,t in TextBox(text:t,confidence:1,rect:UnitRect(x:0.12,y:0.5+Double(i)*0.08,width:0.2,height:0.02)) }
  XCTAssertEqual(SceneClassifier(database:db).classify(lines:lines,heartScores:[0,0,1],skip:false).scene,.topics)
 }
 func testAttachedFlowScreens() {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
  for i in [0,2,3,4] {
   let o=try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("flow-fix-\(i).png").path), preferOptions:false)
   var engine=Engine(database:db)
   if i == 0 {
    _ = engine.next(Observation(scene:.menu,character:"蔻蔻",hearts:3))
    XCTAssertEqual(engine.next(o).point,Engine.center)
    XCTAssertEqual(engine.lockedCharacter,"蔻蔻")
   } else if i == 2 {
    let image = try! loadImage(root.appendingPathComponent("flow-fix-2.png").path)
    let fast = try! VisionReader(database:db).read(image, preferOptions:false, preferHub:true)
    XCTAssertEqual(fast.scene,.hub)
    var animated = fast
    animated.text = "时钟变化 玫瑰动画 背景变化"
    XCTAssertEqual(fast.fingerprint,animated.fingerprint)
    XCTAssertEqual(engine.next(o).point, o.buttons.first { normalize($0.text)=="闲逛" }?.center)
    XCTAssertEqual(engine.next(o).kind,.tap)
    XCTAssertEqual(engine.next(Observation(scene:.loading)).kind,.wait)
   } else {
    XCTAssertEqual(o.scene,.topics)
    _ = engine.next(Observation(scene:.menu,character:"雷斯林",hearts:1,buttons:[TextBox(text:"和他聊聊",confidence:1,rect:UnitRect(x:0.1,y:0.6,width:0.2,height:0.02))]))
    XCTAssertEqual(engine.next(o).kind,.tapAndSkip)
   }
  }
 }
}
