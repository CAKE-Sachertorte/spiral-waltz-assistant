import Foundation
import CoreGraphics
import WaltzCore

final class VisionTests {
    func testFocusedBadgeCropAllowsSmallRegionWithoutWeakeningCalibration() {
        let pixels = [UInt8](repeating: 255, count: 100 * 200 * 4)
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 100, height: 200, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 400,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let badge = UnitRect(x: 0.52, y: 0.706, width: 0.47, height: 0.055)
        XCTAssertEqual(badge.valid, false)
        XCTAssertEqual(cropImage(image, rect: badge) != nil, true)
        XCTAssertNil(cropImage(image, rect: UnitRect(x: 0.99, y: 0.5, width: 0.2, height: 0.1)))
    }
    func testHeartClassificationRequiresConfidentRedness() {
        XCTAssertEqual(HeartClassifier.count(scores: [0.1, 0.92, 0.95]), 2)
        XCTAssertEqual(HeartClassifier.count(scores: [0.91, 0.92, 0.95]), 3)
        XCTAssertEqual(HeartClassifier.count(scores: [0.12, 0.13, 0.11]), 0)
        XCTAssertEqual(HeartClassifier.count(scores: [0.50, 0.92, 0.95]), 2)
        XCTAssertNil(HeartClassifier.count(scores: []))
    }
    func testSceneClassifierDoesNotTreatTopicsAsQuiz() {
        let db = try! GuideDatabase.bundled()
        let lines = [line("返回", 0.45), line("军事", 0.52), line("风物", 0.60), line("政治", 0.68)]
        XCTAssertEqual(SceneClassifier(database: db).classify(lines: lines, heartScores: [0.1,0.9,0.9], skip: false).scene, .topics)
    }
    func testSceneClassifierRecognizesMenuAndLocksBadgeOnly() {
        let db = try! GuideDatabase.bundled()
        let lines = [line("和他聊聊", 0.62), line("一会儿再见", 0.70), line("阿伦", 0.726, 0.75)]
        let o = SceneClassifier(database: db).classify(lines: lines, heartScores: [0.1,0.9,0.9], skip: false)
        XCTAssertEqual(o.scene, .menu)
        XCTAssertEqual(o.character, "阿伦")
        XCTAssertEqual(o.hearts, 2)
    }
    func testRecordedVisionConfidenceForChineseBadgeAndChat() {
        let db = try! GuideDatabase.bundled()
        let lines = [
            TextBox(text: "修伊·奥利奴", confidence: 0.3, rect: UnitRect(x:0.60,y:0.72,width:0.30,height:0.02)),
            TextBox(text: "和他聊聊", confidence: 0.3, rect: UnitRect(x:0.08,y:0.60,width:0.25,height:0.02)),
            line("一会儿再见", 0.69), line("打听情报", 0.55)
        ]
        let o = SceneClassifier(database: db).classify(lines: lines, heartScores: [1,1,1], skip: false)
        XCTAssertEqual(o.scene, .menu)
        XCTAssertEqual(o.character, "修伊")
    }
    func testQuizOptionsUseVisibleOrder() {
        let db = try! GuideDatabase.bundled()
        let lines = [line("绿色", 0.61), line("黑色", 0.45), line("红色", 0.69), line("蓝色", 0.53), line("玛格达最喜欢的颜色是", 0.82)]
        let o = SceneClassifier(database: db).classify(lines: lines, heartScores: [0.9,0.9,0.9], skip: false)
        XCTAssertEqual(o.scene, .answers)
        XCTAssertEqual(o.buttons.map(\.text), ["黑色", "蓝色", "绿色", "红色"])
    }
    func testForbiddenScreenWinsOverDialogueHeuristic() {
        let db = try! GuideDatabase.bundled()
        let lines = [line("任务信息", 0.08), line("离开舞会", 0.69), line("现在该做什么呢", 0.82)]
        XCTAssertEqual(SceneClassifier(database: db).classify(lines: lines, heartScores: [1,1,1], skip: false).scene, .blocked)
    }
    private func line(_ text: String, _ y: Double, _ x: Double = 0.20) -> TextBox {
        TextBox(text: text, confidence: 0.99, rect: UnitRect(x: x - 0.10, y: y - 0.01, width: 0.20, height: 0.02))
    }
}
