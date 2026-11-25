import Foundation
import CoreGraphics
import ImageIO
import Vision

public struct PixelImage {
    public let width: Int
    public let height: Int
    private let data: [UInt8]
    public init(_ image: CGImage) throws {
        let width = image.width, height = image.height
        self.width = width; self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { throw CocoaError(.coderInvalidValue) }
        data = bytes
    }
    public func rgb(x: Int, y: Int) -> (Double, Double, Double) {
        let i = (max(0, min(height - 1, y)) * width + max(0, min(width - 1, x))) * 4
        return (Double(data[i]) / 255, Double(data[i+1]) / 255, Double(data[i+2]) / 255)
    }
    public func heartScores(centerY: Double = 0.684) -> [Double] {
        [0.747, 0.829, 0.910].map { x in
            var colored = 0.0, total = 0.0
            // Small interior patch, away from the white outline and heart animation edge.
            for py in -5...5 { for px in -7...7 {
                let (r,g,b) = rgb(x: Int(x * Double(width)) + Int(Double(px) * Double(width) / 788),
                                  y: Int(centerY * Double(height)) + Int(Double(py) * Double(width) / 788))
                total += 1
                // Unlit translucent hearts can inherit red from a costume underneath.
                // Filled hearts also have a bright red channel; hue alone is insufficient.
                if r - (g + b) / 2 > 0.34 && r > 0.80 { colored += 1 }
            }}
            return colored / max(1, total)
        }
    }
    public func skipVisible() -> Bool {
        var white = 0.0, total = 0.0
        let cx = Int(Engine.skipPoint.x * Double(width)), cy = Int((Double(width) / Double(height) > 0.52 ? 0.975 : Engine.skipPoint.y) * Double(height))
        let radius = max(8, Int(Double(width) * 0.032))
        for py in -radius...radius { for px in -radius...radius {
            let (r,g,b) = rgb(x: cx + px, y: cy + py)
            total += 1
            if min(r, min(g,b)) > 0.60 && max(r, max(g,b)) - min(r,min(g,b)) < 0.18 { white += 1 }
        }}
        return white / total > 0.09
    }
}

public final class VisionReader {
    private let database: GuideDatabase
    public init(database: GuideDatabase) { self.database = database }
    public func read(_ image: CGImage, preferOptions: Bool = true, preferHub: Bool = false) throws -> Observation {
        if preferHub {
            let lines = try regionLines(image, region: UnitRect(x: 0.65, y: 0.32, width: 0.35, height: 0.45))
            let hub = SceneClassifier(database: database).classify(lines: lines, heartScores: [], skip: false)
            if hub.scene == .hub { return hub }
        }
        if preferOptions, let quiz = try readOptions(image) { return quiz }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008
        request.customWords = database.characters.flatMap { [$0.name] + $0.aliases } + Array(SceneClassifier.menuLabels) + ["和她聊聊", "返回", "军事", "风物", "冒险", "人际", "艺术", "时尚", "娱乐", "商业", "政治", "神秘", "玛格达"]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var lines = (request.results ?? []).compactMap { observation -> TextBox? in
            guard let text = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return TextBox(text: text.string, confidence: text.confidence,
                           rect: UnitRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
        // The purple badge is easy to miss when Vision analyzes the whole illustrated scene.
        // Retry this small region on its own only if the first pass cannot identify a name.
        let badge = UnitRect(x: 0.52, y: 0.66, width: 0.47, height: 0.16)
        let hasName = lines.contains { $0.center.y > 0.66 && $0.center.y < 0.82 && $0.center.x > 0.48 && database.character(named: $0.text) != nil }
        if !hasName, let nameImage = cropImage(image, rect: badge) {
            let focused = VNRecognizeTextRequest()
            focused.recognitionLevel = .accurate
            focused.recognitionLanguages = ["zh-Hans"]
            focused.usesLanguageCorrection = false
            focused.customWords = request.customWords
            try VNImageRequestHandler(cgImage: nameImage, options: [:]).perform([focused])
            for result in focused.results ?? [] {
                guard let candidate = result.topCandidates(1).first, database.character(named: candidate.string) != nil else { continue }
                let b = result.boundingBox
                lines.append(TextBox(text: candidate.string, confidence: max(0.3, candidate.confidence),
                                     rect: UnitRect(x: badge.x + b.minX * badge.width, y: badge.y + (1 - b.maxY) * badge.height,
                                                    width: b.width * badge.width, height: b.height * badge.height)))
            }
        }
        let pixels = try PixelImage(image)
        let classifier = SceneClassifier(database: database)
        let wideLayout = Double(image.width) / Double(image.height) > 0.52
        let scores = try recognizedHeartScores(image, lines: lines), skip = pixels.skipVisible()
        let initial = classifier.classify(lines: lines, heartScores: scores, skip: skip, wideLayout: wideLayout)
        // On dark buttons Vision can omit an entire label, even when neighboring buttons
        // are recognized. Re-read only the menu, accepting exact known labels and positions.
        let partialMenu = initial.character != nil && (initial.scene == .unknown || initial.scene == .dialogue)
            && lines.contains { $0.center.x < 0.48 && (0.32...0.77).contains($0.center.y) && SceneClassifier.menuLabels.contains(normalize($0.text)) }
        if initial.scene == .menu || partialMenu {
            let menu = UnitRect(x: 0.015, y: 0.32, width: 0.61, height: 0.45)
            if let menuImage = cropImage(image, rect: menu) {
                let focused = VNRecognizeTextRequest()
                focused.recognitionLevel = .accurate
                focused.recognitionLanguages = ["zh-Hans"]
                focused.usesLanguageCorrection = false
                focused.minimumTextHeight = 0.015
                focused.customWords = Array(SceneClassifier.menuLabels) + ["和她聊聊", "跳过"]
                try VNImageRequestHandler(cgImage: menuImage, options: [:]).perform([focused])
                for result in focused.results ?? [] {
                    guard let candidate = result.topCandidates(1).first, candidate.confidence >= 0.25,
                          (SceneClassifier.menuLabels.contains(normalize(candidate.string)) || normalize(candidate.string) == "跳过") else { continue }
                    let b = result.boundingBox
                    let recovered = TextBox(text: candidate.string, confidence: candidate.confidence,
                                            rect: UnitRect(x: menu.x + b.minX * menu.width, y: menu.y + (1 - b.maxY) * menu.height,
                                                           width: b.width * menu.width, height: b.height * menu.height))
                    guard !lines.contains(where: { normalize($0.text) == normalize(recovered.text) && abs($0.center.y - recovered.center.y) < 0.025 && $0.center.x < 0.48 && $0.confidence >= 0.25 }) else { continue }
                    lines.append(recovered)
                }
            }
        }
        if initial.scene == .unknown || initial.scene == .danceScene || normalize(initial.text).contains("查看攻略") {
            // White competition labels can be missed against the illustrated background.
            // Locate the text in its button area; never fall back to a fixed click point.
            let focused = try regionLines(image, region: UnitRect(x: 0.72, y: 0.80, width: 0.27, height: 0.19))
            lines += focused.filter { normalize($0.text) == "跳过" && $0.confidence >= 0.25 }
        }
        return classifier.classify(lines: lines, heartScores: scores, skip: skip, wideLayout: wideLayout)
    }
    private func readOptions(_ image: CGImage) throws -> Observation? {
        let classifier = SceneClassifier(database: database)
        let wideLayout = Double(image.width) / Double(image.height) > 0.52
        let optionY = wideLayout ? 0.29 : 0.38
        let optionHeight = wideLayout ? 0.45 : 0.35
        // Questions can appear on either side depending on who is speaking.
        for region in [UnitRect(x: 0.015, y: optionY, width: 0.40, height: optionHeight),
                       UnitRect(x: 0.65, y: optionY, width: 0.35, height: optionHeight)] {
            var lines = try regionLines(image, region: region)
            guard classifier.classify(lines: lines, heartScores: [], skip: false, wideLayout: wideLayout).scene == .answers else { continue }
            lines += try regionLines(image, region: UnitRect(x: 0.015, y: wideLayout ? 0.66 : 0.706, width: 0.97, height: wideLayout ? 0.09 : 0.055))
            let quiz = classifier.classify(lines: lines, heartScores: try recognizedHeartScores(image, lines: lines), skip: false, wideLayout: wideLayout)
            guard quiz.scene == .answers, let name = quiz.character else { continue }
            if name == "玛格达" {
                // Only promote a complete known option set. Partial/misread choices must
                // still get the full-frame pass; the engine retains the actual NPC target.
                let keys = quiz.buttons.map { normalize($0.text) }
                let complete = database.questions.contains { q in
                    let known = Set(q.answers.values.flatMap { $0 }.map(normalize))
                    return q.answers.count == keys.count && Set(keys).count == keys.count && keys.allSatisfy { known.contains($0) }
                }
                if complete { return quiz }
            } else if quiz.hearts == 3, database.answer(character: name, text: "", options: quiz.buttons.map(\.text)) != nil {
                return quiz
            }
        }
        return nil
    }
    private func recognizedHeartScores(_ image: CGImage, lines: [TextBox]) throws -> [Double] {
        let badgeCenter = lines.first { $0.center.x > 0.48 && (0.66...0.82).contains($0.center.y) && database.character(named: $0.text) != nil }?.center.y
        let wide = Double(image.width) / Double(image.height) > 0.52
        let centerY = wide ? badgeCenter.map { $0 - 0.091 * Double(image.width) / Double(image.height) } ?? 0.684 : 0.684
        return try PixelImage(image).heartScores(centerY: centerY)
    }
    private func regionLines(_ image: CGImage, region: UnitRect) throws -> [TextBox] {
        guard let cropped = cropImage(image, rect: region) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
        try VNImageRequestHandler(cgImage: cropped, options: [:]).perform([request])
        return (request.results ?? []).compactMap { result in
            guard let candidate = result.topCandidates(1).first else { return nil }
            let b = result.boundingBox
            return TextBox(text: candidate.string, confidence: candidate.confidence,
                           rect: UnitRect(x: region.x + b.minX * region.width, y: region.y + (1 - b.maxY) * region.height,
                                          width: b.width * region.width, height: b.height * region.height))
        }
    }
}

public func cropImage(_ image: CGImage, rect: UnitRect) -> CGImage? {
    // OCR regions can be much smaller than a valid full-game calibration rectangle.
    guard rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0,
          rect.x + rect.width <= 1.001, rect.y + rect.height <= 1.001 else { return nil }
    return image.cropping(to: CGRect(x: rect.x * Double(image.width), y: rect.y * Double(image.height),
                                    width: rect.width * Double(image.width), height: rect.height * Double(image.height)).integral)
}
public func loadImage(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
    return image
}
public func writePNG(_ image: CGImage, path: String) throws {
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}
