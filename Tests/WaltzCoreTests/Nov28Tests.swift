import Foundation
import CoreGraphics
import WaltzCore

final class Nov28Tests {
    let db = try! GuideDatabase.bundled()
    func read(_ fixture: Int, width: Int) -> Observation {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let image = try! loadImage(root.appendingPathComponent("nov28-\(fixture).png").path)
        let height = Int(Double(width) * Double(image.height) / Double(image.width))
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        c.interpolationQuality = .high
        c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try! VisionReader(database: db).read(c.makeImage()!, preferOptions: false)
    }
    func testNaerBadgeAndIntelligenceAcrossSizes() {
        for width in [330, 440, 598, 788] {
            let o = read(1, width: width)
            XCTAssertEqual(o.scene, .menu)
            XCTAssertEqual(o.character, "娜尔")
            XCTAssertEqual(o.hearts, 3)
            var engine = Engine(database: db)
            let action = engine.next(o)
            XCTAssertEqual(action.kind, .tapAndSkip)
            XCTAssertEqual(action.point, o.buttons.first { normalize($0.text) == "打听情报" }?.center)
        }
    }
    func testAlminasTopicsDoNotBecomeAnUnstartedQuiz() {
        for width in [240, 469, 788] {
            let o = read(2, width: width)
            XCTAssertEqual(o.scene, .topics)
            XCTAssertEqual(o.buttons.contains { normalize($0.text) == "冒险" }, true)
            var engine = Engine(database: db)
            _ = engine.next(Observation(scene: .menu, character: "阿尔米纳斯", hearts: 1,
                buttons: [TextBox(text: "和他聊聊", confidence: 1, rect: UnitRect(x: 0.1, y: 0.6, width: 0.25, height: 0.03))]))
            let action = engine.next(o)
            XCTAssertEqual(action.kind, .tapAndSkip)
            XCTAssertEqual(action.point, o.buttons.first { normalize($0.text) == "冒险" }?.center)
        }
    }
}
