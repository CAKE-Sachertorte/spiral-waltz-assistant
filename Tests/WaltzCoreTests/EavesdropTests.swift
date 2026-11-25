import Foundation
import WaltzCore
final class EavesdropTests {
 let db = try! GuideDatabase.bundled()
 func testAttachedVariantChoosesLowerOption() {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
  let o=try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("eavesdrop-variant.png").path),preferOptions:false)
  var engine=Engine(database:db)
  XCTAssertEqual(o.scene,.eavesdrop)
  XCTAssertEqual(o.buttons.map(\.text),["有点好奇","不关我事"])
  let action=engine.next(o)
  XCTAssertEqual(action.kind,.tap)
  XCTAssertEqual(action.point,o.buttons.last?.center)
 }
 func testWanderingTwoChoiceEventDoesNotDependOnWords() {
  func line(_ text:String,_ y:Double)->TextBox { TextBox(text:text,confidence:1,rect:UnitRect(x:0.73,y:y,width:0.24,height:0.025)) }
  let choices=[line("任意上项",0.52),line("任意下项",0.63)]
  let hero=TextBox(text:"玛格达",confidence:1,rect:UnitRect(x:0.1,y:0.72,width:0.2,height:0.02))
  let o=SceneClassifier(database:db).classify(lines:choices+[hero],heartScores:[0,0,0],skip:false)
  var engine=Engine(database:db)
  let nav=[line("闲逛",0.50),line("找人",0.60)]
  _ = engine.next(SceneClassifier(database:db).classify(lines:nav,heartScores:[],skip:false))
  XCTAssertEqual(engine.next(o).point,choices[1].center)
  var quiz=Engine(database:db)
  let start=TextBox(text:"好感度问答",confidence:1,rect:UnitRect(x:0.1,y:0.5,width:0.2,height:0.02))
  _ = quiz.next(Observation(scene:.menu,character:"露西莉亚",hearts:3,buttons:[start]))
  XCTAssertEqual(quiz.next(o).kind,.wait)
  var fresh=Engine(database:db)
  XCTAssertEqual(fresh.next(o).point,choices[1].center)
 }
}
