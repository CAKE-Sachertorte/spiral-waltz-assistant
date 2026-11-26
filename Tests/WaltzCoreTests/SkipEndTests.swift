import Foundation
import WaltzCore
final class SkipEndTests {
 let db = try! GuideDatabase.bundled()
 func testCompetitionUsesSkipAndFallsBackToCenter() {
  var engine=Engine(database:db)
  let beauty=TextBox(text:"主动比美",confidence:1,rect:UnitRect(x:0.1,y:0.5,width:0.2,height:0.02))
  _ = engine.next(Observation(scene:.menu,character:"凌格兰",hearts:3,buttons:[beauty]))
  XCTAssertEqual(engine.next(Observation(scene:.unknown)).point,Engine.center)
  let skip=TextBox(text:"跳过",confidence:1,rect:UnitRect(x:0.80,y:0.85,width:0.1,height:0.025))
  let scene=Observation(scene:.danceScene,lines:[skip])
  XCTAssertEqual(engine.next(scene).point,skip.center)
  XCTAssertEqual(engine.next(scene).point,skip.center)
  XCTAssertEqual(engine.next(Observation(scene:.unknown)).point,Engine.center)
  XCTAssertEqual(engine.next(Observation(scene:.danceScene,text:"总分")).point,Engine.center)
 }
 func testPartialExhaustionStops() {
  var engine=Engine(database:db)
  XCTAssertEqual(engine.next(Observation(scene:.dialogue,text:"如果想要和人聊天的话，似乎还是直接找")).kind,.done)
 }
 func testAttachedScreens() {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
  let end=try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("skip-end-0.png").path),preferOptions:false)
  var engine=Engine(database:db)
  XCTAssertEqual(engine.next(end).kind,.done)
  let competition=try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("skip-end-1.png").path),preferOptions:false)
  let beauty=TextBox(text:"主动比美",confidence:1,rect:UnitRect(x:0.1,y:0.5,width:0.2,height:0.02))
  var playing=Engine(database:db)
  _ = playing.next(Observation(scene:.menu,character:"凌格兰",hearts:3,buttons:[beauty]))
  let action=playing.next(competition)
  XCTAssertEqual(action.kind,.tap)
  XCTAssertEqual(action.point.map { $0.x > 0.8 && $0.y > 0.85 },true)
 }
}
