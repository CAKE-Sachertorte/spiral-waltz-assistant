import Foundation
import WaltzCore
final class NativeClientTests {
 func testMenuDanceSkipIsRecovered() {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
  let db=try! GuideDatabase.bundled()
  let o=try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("andre-menu-skip.png").path),preferOptions:false)
  var engine=Engine(database:db)
  let a=engine.next(o)
  XCTAssertEqual(a.kind,.tap)
  XCTAssertEqual(a.point.map { $0.x > 0.38 && $0.x < 0.62 && $0.y < 0.65 },true)
 }
 func testNativeClientDialogue() {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
  let db=try! GuideDatabase.bundled()
  let o=try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("native-client-menu.png").path),preferOptions:false)
  XCTAssertEqual(o.scene,.dialogue)
  XCTAssertEqual(o.character,"露西莉亚")
  XCTAssertEqual(o.hearts,0)
  var engine=Engine(database:db)
  XCTAssertEqual(engine.next(o).kind,.tap)
 }
}
