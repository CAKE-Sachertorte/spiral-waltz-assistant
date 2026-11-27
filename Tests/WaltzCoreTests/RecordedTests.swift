import Foundation
import CoreGraphics
import WaltzCore

final class RecordedTests {
    func testRealRecordingOCRObservations() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let db = try! GuideDatabase.bundled()
        for (file, scene, name) in [("menu-shui", Scene.menu, "修伊"), ("menu-andre", Scene.menu, "安德烈·沃尔夫"), ("dialogue-skip", Scene.dialogue, ""), ("reward", Scene.reward, "")] {
            let data = try! Data(contentsOf: root.appendingPathComponent(file + ".json"))
            let recorded = try! JSONDecoder().decode(Observation.self, from: data)
            let actual = SceneClassifier(database: db).classify(lines: recorded.lines, heartScores: recorded.heartScores, skip: recorded.skipVisible)
            XCTAssertEqual(actual.scene, scene)
            if !name.isEmpty { XCTAssertEqual(actual.character, name); XCTAssertEqual(actual.hearts, 3) }
            if file == "dialogue-skip" { XCTAssertEqual(actual.skipVisible, true) }
        }
    }
    func testLiveNikosiMenuRecoversMissingChatLabel() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let image = try! loadImage(root.appendingPathComponent("menu-nikosi-window.png").path)
        let game = cropImage(image, rect: UnitRect(x: 0.0195, y: 0.0423, width: 0.961, height: 0.949))!
        let db = try! GuideDatabase.bundled()
        let observation = try! VisionReader(database: db).read(game)
        XCTAssertEqual(observation.character, "妮柯斯")
        XCTAssertEqual(observation.hearts, 2)
        XCTAssertEqual(observation.buttons.contains { normalize($0.text) == "和他聊聊" }, true)
        var engine = Engine(database: db)
        let decision = engine.next(observation)
        XCTAssertEqual(decision.kind, .tap)
        XCTAssertEqual(decision.point.map { (0.58...0.66).contains($0.y) }, true)
    }
    func testAttachedMargdaQuestionBadges() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let db = try! GuideDatabase.bundled()
        for i in 0..<2 {
            let image = try! loadImage(root.appendingPathComponent("margda-quiz-\(i).png").path)
            let observation = try! VisionReader(database: db).read(image, preferOptions: false)
            XCTAssertEqual(observation.scene, .answers)
            XCTAssertEqual(observation.character, "玛格达")
        }
    }
    func testAttachedIntelligenceRewardScreens() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let db = try! GuideDatabase.bundled()
        for i in 0..<2 {
            let image = try! loadImage(root.appendingPathComponent("intelligence-reward-\(i).png").path)
            let observation = try! VisionReader(database: db).read(image, preferOptions: false)
            XCTAssertEqual(observation.scene, .reward)
            var engine = Engine(database: db)
            let intel = TextBox(text: "打听情报", confidence: 1, rect: UnitRect(x: 0.1, y: 0.5, width: 0.2, height: 0.02))
            _ = engine.next(Observation(scene: .menu, character: "蒂拉", hearts: 3, buttons: [intel]))
            XCTAssertEqual(engine.next(observation).kind, .tap)
        }
    }
    func testBarisQuizUsesOptionRegionWithoutReadingStem() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let image = try! loadImage(root.appendingPathComponent("quiz-baris-structure-window.png").path)
        let game = cropImage(image, rect: UnitRect(x: 0.020790554163567346, y: 0.03901233948635634, width: 0.9541569302255021, height: 0.9527425260834671))!
        let db = try! GuideDatabase.bundled()
        let observation = try! VisionReader(database: db).read(game)
        XCTAssertEqual(observation.scene, .answers)
        XCTAssertEqual(observation.character, "巴里斯")
        XCTAssertEqual(observation.lines.allSatisfy { $0.center.y < 0.79 }, true)
        XCTAssertEqual(db.answer(character: "巴里斯", text: observation.text, options: observation.buttons.map(\.text))?.index, 3)
        var engine = Engine(database: db)
        XCTAssertEqual(engine.next(observation).point, observation.buttons.last?.center)
    }
    func testOriginalFullHeartsRemainRecognized() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        for name in ["menu-shui-full-video", "menu-andre-full-video"] {
            let image = try! loadImage(root.appendingPathComponent(name + ".png").path)
            let game = cropImage(image, rect: UnitRect(x: 0.122, y: 0.075, width: 0.757, height: 0.846))!
            XCTAssertEqual(HeartClassifier.count(scores: try! PixelImage(game).heartScores()), 3)
        }
    }
    func testAndreUnlitHeartOverRedCostume() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let image = try! loadImage(root.appendingPathComponent("menu-andre-two-hearts-window.png").path)
        let rects = [UnitRect(x: 0.020790554163567346, y: 0.03901233948635634, width: 0.9541569302255021, height: 0.9527425260834671),
                     UnitRect(x: 0.0195, y: 0.0423, width: 0.961, height: 0.949)]
        for rect in rects {
            let game = cropImage(image, rect: rect)!
            let scores = try! PixelImage(game).heartScores()
            XCTAssertEqual(HeartClassifier.count(scores: scores), 2)
            let db = try! GuideDatabase.bundled()
            let lines = [TextBox(text: "安德烈·沃尔夫", confidence: 1, rect: UnitRect(x: 0.61, y: 0.72, width: 0.3, height: 0.02)),
                         TextBox(text: "和他聊聊", confidence: 1, rect: UnitRect(x: 0.08, y: 0.61, width: 0.25, height: 0.02))]
            let observation = SceneClassifier(database: db).classify(lines: lines, heartScores: scores, skip: false)
            var engine = Engine(database: db)
            XCTAssertEqual(engine.next(observation).kind, .tap)
        }
    }
    func testHeartPixelsWithDarkAndLightCostumeBackgrounds() {
        let w = 788, h = 1706
        for dim: [UInt8] in [[122,70,81,255], [244,174,178,255], [190,95,95,255]] {
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            for (slot,x) in [0.747,0.829,0.910].enumerated() {
                for dy in -15...15 { for dx in -20...20 {
                    let offset = ((Int(0.684 * Double(h)) + dy) * w + Int(x * Double(w)) + dx) * 4
                    let rgba: [UInt8] = slot == 0 ? dim : [230,104,116,255]
                    for i in 0..<4 { bytes[offset+i] = rgba[i] }
                }}
            }
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let image = CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            let score = try! PixelImage(image).heartScores()
            XCTAssertEqual(HeartClassifier.count(scores: score), 2)
        }
    }
}
