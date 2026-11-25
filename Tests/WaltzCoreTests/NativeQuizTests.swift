import Foundation
import WaltzCore
final class NativeQuizTests {
 func testFirstNativeQuizOptionIsNotClipped() {
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
  let db=try! GuideDatabase.bundled()
  for prefer in [false,true] {
  let o=try! VisionReader(database:db).read(loadImage(root.appendingPathComponent("native-lucilia-quiz.png").path),preferOptions:prefer)
  XCTAssertEqual(o.hearts,3)
  XCTAssertEqual(o.buttons.map(\.text),["荒唐可笑","文明开化","平民的胜利","权力博弈"])
  XCTAssertEqual(db.answer(character:"露西莉亚",text:o.text,options:o.buttons.map(\.text))?.index,0)
  }
 }
}
