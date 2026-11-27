import Foundation
import CoreGraphics
import WaltzCore
final class GonzaloScaleTests {
    let db=try! GuideDatabase.bundled()
    func testGonzaloBadgeAcrossCaptureSizes() {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let image=try! loadImage(root.appendingPathComponent("nov27d-1.png").path)
        for width in [500,788] {
            let height=Int(Double(width)*Double(image.height)/Double(image.width))
            let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
            c.interpolationQuality = .high
            c.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            let o=try! VisionReader(database:db).read(c.makeImage()!,preferOptions:false)
            XCTAssertEqual(o.scene,.menu)
            XCTAssertEqual(o.character,"冈萨洛")
            XCTAssertEqual(o.hearts,0)
            var e=Engine(database:db)
            let action=e.next(o)
            XCTAssertEqual(action.kind,.tap)
            XCTAssertEqual(action.point,o.buttons.first{normalize($0.text)=="和他聊聊"}?.center)
        }
    }
    func testGonzaloMisreadIsLimitedToExactBadgeNames() {
        XCTAssertEqual(db.badgeName(from:"网萨洛·乔卡瑟尔"),"冈萨洛")
        XCTAssertEqual(db.badgeName(from:"网萨洛"),"冈萨洛")
        XCTAssertNil(db.badgeName(from:"我听说网萨洛"))
        XCTAssertNil(db.badgeName(from:"网萨洛的故事"))
        XCTAssertNil(db.character(named:"网萨洛"))
    }
}
