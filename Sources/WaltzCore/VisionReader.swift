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
        request.customWords = database.characters.flatMap { [$0.name] + $0.aliases } + Array(SceneClassifier.menuLabels) + ["和她聊聊", "返回", "军事", "风物", "冒险", "人际", "艺术", "时尚", "娱乐", "商业", "政治", "神秘", "玛格达", "冈萨洛·乔卡瑟尔", "琳娜·乔卡瑟尔", "劳伦斯·乔卡瑟尔", "玛菲利娅", "玛菲利娅·赫尔"]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        var lines = (request.results ?? []).compactMap { observation -> TextBox? in
            guard let text = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return TextBox(text: text.string, confidence: text.confidence,
                           rect: UnitRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
        // The purple badge is easy to miss when Vision analyzes the whole illustrated scene.
        // Retry this small region on its own only if the first pass cannot identify a name.
        let hasName = lines.contains { $0.confidence >= 0.25 && $0.center.y > 0.66 && $0.center.y < 0.82 && $0.center.x > 0.48 && database.badgeName(from: $0.text) != nil }
        if !hasName {
            let badges = [UnitRect(x: 0.52, y: 0.66, width: 0.47, height: 0.16)]
                + [0.66, 0.71, 0.755].map { UnitRect(x: 0.52, y: $0, width: 0.47, height: 0.065) }
            for badge in badges {
                guard let nameImage = cropImage(image, rect: badge) else { continue }
                // Short names can disappear or change characters at small capture sizes.
                // Retry the same pixels enlarged, rather than treating a misread as an alias.
                let samples = nameImage.width < 600 ? [nameImage, textImage(nameImage, minimumWidth: 600)] : [nameImage]
                for sample in samples {
                    let focused = VNRecognizeTextRequest()
                    focused.recognitionLevel = .accurate
                    focused.recognitionLanguages = ["zh-Hans"]
                    focused.usesLanguageCorrection = false
                    focused.customWords = request.customWords
                    try VNImageRequestHandler(cgImage: sample, options: [:]).perform([focused])
                    for result in focused.results ?? [] {
                        guard let candidate = result.topCandidates(5).first(where: { database.badgeName(from: $0.string) != nil }) else { continue }
                        let b = result.boundingBox
                        let rect = UnitRect(x: badge.x + b.minX * badge.width, y: badge.y + (1 - b.maxY) * badge.height,
                                            width: b.width * badge.width, height: b.height * badge.height)
                        guard rect.center.x > 0.48 && (0.66...0.82).contains(rect.center.y) else { continue }
                        lines.append(TextBox(text: candidate.string, confidence: max(0.3, candidate.confidence), rect: rect))
                    }
                    if lines.contains(where: { $0.confidence >= 0.25 && $0.center.x > 0.48 && (0.66...0.82).contains($0.center.y) && database.badgeName(from: $0.text) != nil }) { break }
                }
                if lines.contains(where: { $0.confidence >= 0.25 && $0.center.x > 0.48 && (0.66...0.82).contains($0.center.y) && database.badgeName(from: $0.text) != nil }) { break }
            }
        }
        let pixels = try PixelImage(image)
        let classifier = SceneClassifier(database: database)
        let wideLayout = Double(image.width) / Double(image.height) > 0.52
        let scores = try recognizedHeartScores(image, lines: lines), skip = pixels.skipVisible()
        let initial = classifier.classify(lines: lines, heartScores: scores, skip: skip, wideLayout: wideLayout)
        // On dark buttons Vision can omit an entire label, even when neighboring buttons
        // are recognized. Re-read only the menu, accepting exact known labels and positions.
        let partialMenu = initial.character != nil && [.unknown, .dialogue, .answers].contains(initial.scene)
        if initial.scene == .menu || partialMenu {
            // Keep portraits out of the text crop; their details can split short labels.
            for width in [0.61, 0.40] {
                let recovered = try regionLines(image, region: UnitRect(x: 0.015, y: 0.32, width: width, height: 0.45))
                for b in recovered where b.confidence >= 0.25 && (SceneClassifier.menuLabels.contains(normalize(b.text)) || normalize(b.text) == "跳过") {
                    if lines.contains(where: { normalize($0.text) == normalize(b.text) && $0.confidence >= b.confidence && abs($0.center.y - b.center.y) < 0.025 && abs($0.center.x - b.center.x) < 0.10 }) { continue }
                    lines.removeAll { abs($0.center.y - b.center.y) < 0.025 && abs($0.center.x - b.center.x) < 0.10 }
                    lines.append(b)
                }
            }
        }
        // A failed whole-frame read may call a topic list an answer page. Verify the
        // column independently before accepting that classification; never infer a topic
        // from row count or from the engine's phase.
        if [.topics, .answers, .dialogue, .unknown].contains(initial.scene) {
            let recovered = try regionLines(image, region: UnitRect(x: 0.015, y: 0.32, width: 0.40, height: 0.45),
                                            words: Array(SceneClassifier.topicLabels) + ["返回"], minimumWidth: 600)
                .filter { $0.confidence >= 0.25 && (SceneClassifier.topicLabels.contains(normalize($0.text)) || normalize($0.text) == "返回") }
            if classifier.classify(lines: recovered, heartScores: [], skip: false, wideLayout: wideLayout).scene == .topics {
                for b in recovered {
                    lines.removeAll { abs($0.center.y - b.center.y) < 0.025 && abs($0.center.x - b.center.x) < 0.10 }
                    lines.append(b)
                }
            }
        }
        let topicView = classifier.classify(lines: lines, heartScores: scores, skip: skip, wideLayout: wideLayout)
        if topicView.scene == .topics {
            // An omitted row has no box to retry. Overlapping strips recover its text
            // only after the page is independently confirmed as a topic list.
            if Set(topicView.buttons.map { normalize($0.text) }).intersection(SceneClassifier.topicLabels).count < 3 {
                for y in [0.32, 0.41, 0.50, 0.59, 0.63] {
                    let recovered = try regionLines(image, region: UnitRect(x: 0.015, y: y, width: 0.40, height: 0.14),
                                                    words: Array(SceneClassifier.topicLabels), minimumWidth: 600)
                    for b in recovered where b.confidence >= 0.25 && SceneClassifier.topicLabels.contains(normalize(b.text)) {
                        lines.removeAll { abs($0.center.y - b.center.y) < 0.025 && abs($0.center.x - b.center.x) < 0.10 }
                        lines.append(b)
                    }
                }
            }
            // A whole column can still misread one topic. Re-read that row with padding.
            for row in topicView.buttons where row.center.x < 0.38 && !SceneClassifier.topicLabels.contains(normalize(row.text)) && normalize(row.text) != "返回" {
                let y = max(0.32, floor(row.rect.y * 100) / 100 - 0.02)
                let h = min(0.77 - y, max(0.075, row.rect.height + 0.05))
                let recovered = try regionLines(image, region: UnitRect(x: 0.015, y: y, width: 0.40, height: h))
                lines += recovered.filter { SceneClassifier.topicLabels.contains(normalize($0.text)) }
            }
        }
        if initial.scene == .unknown || initial.scene == .danceScene || normalize(initial.text).contains("查看攻略") {
            // White competition labels can be missed against the illustrated background.
            // Re-read the whole bottom strip: the final continue hint is centered,
            // while the skip button sits on the right. Both can be missed in full OCR.
            let focused = try regionLines(image, region: UnitRect(x: 0.015, y: 0.79, width: 0.97, height: 0.19))
            lines += focused.filter {
                let key = normalize($0.text)
                return $0.confidence >= 0.25 && (["跳过", "查看攻略"].contains(key) || key.contains("点击屏幕继"))
            }
        }
        if initial.scene == .danceScene && !lines.contains(where: {
            $0.confidence >= 0.25 && normalize($0.text) == "跳过" && $0.center.x > 0.70 && $0.center.y > 0.70
        }) {
            // Thin overlapping rows exclude costume frames that merge into the label
            // in a large crop. Accept only an actual exact OCR label, never a fixed tap.
            for row in 0..<10 {
                let region = UnitRect(x: 0.70, y: 0.795 + Double(row) * 0.015, width: 0.29, height: 0.035)
                let recovered = try regionLines(image, region: region, words: ["跳过"])
                    .filter { $0.confidence >= 0.25 && normalize($0.text) == "跳过" && $0.center.x > 0.70 }
                if !recovered.isEmpty { lines += recovered; break }
            }
        }
        let result = classifier.classify(lines: lines, heartScores: scores, skip: skip, wideLayout: wideLayout)
        if !preferOptions && result.scene == .answers, let quiz = try readOptions(image) { return quiz }
        return result
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
            let first = classifier.classify(lines: lines, heartScores: [], skip: false, wideLayout: wideLayout)
            guard first.scene == .answers else { continue }
            if first.buttons.count == 3 {
                // A tiny crop shift can recover a single-character option dropped by Vision.
                // Adopt it only when it reveals a complete, known four-option question.
                let alternate = try regionLines(image, region: UnitRect(x: region.x, y: region.y + 0.01, width: region.width, height: region.height))
                let keys = classifier.classify(lines: alternate, heartScores: [], skip: false, wideLayout: wideLayout).buttons.map { GuideDatabase.answerKey($0.text) }
                if keys.count == 4 && Set(keys).count == 4 && database.questions.contains(where: { q in
                    let known = Set(q.answers.values.flatMap { $0 }.map(GuideDatabase.answerKey))
                    return q.answers.count == 4 && keys.allSatisfy { known.contains($0) }
                }) { lines = alternate }
            }
            // Restrict a retry's vocabulary to a question identified by multiple exact
            // choices. Only adopt a complete distinct set; never infer the unread answer.
            let keys = first.buttons.map { GuideDatabase.answerKey($0.text) }
            let candidates = database.questions.filter { q in
                let known = Set(q.answers.values.flatMap { $0 }.map(GuideDatabase.answerKey))
                return keys.filter { known.contains($0) }.count >= 2
            }
            if candidates.count == 1, let question = candidates.first {
                let known = Set(question.answers.values.flatMap { $0 }.map(GuideDatabase.answerKey))
                if keys.count != question.answers.count || !keys.allSatisfy({ known.contains($0) }) {
                    let words = question.answers.values.flatMap { $0 } + ["隐身魔法"]
                    let retry = try regionLines(image, region: region, words: words)
                    let recovered = classifier.classify(lines: retry, heartScores: [], skip: false, wideLayout: wideLayout).buttons.map { GuideDatabase.answerKey($0.text) }
                    if recovered.count == question.answers.count && Set(recovered).count == recovered.count && recovered.allSatisfy({ known.contains($0) }) { lines = retry }
                }
            }
            lines += try regionLines(image, region: UnitRect(x: 0.015, y: wideLayout ? 0.66 : 0.706, width: 0.97, height: wideLayout ? 0.09 : 0.055))
            let quiz = classifier.classify(lines: lines, heartScores: try recognizedHeartScores(image, lines: lines), skip: false, wideLayout: wideLayout)
            guard quiz.scene == .answers, let name = quiz.character else { continue }
            if name == "玛格达" {
                // Only promote a complete known option set. Partial/misread choices must
                // still get the full-frame pass; the engine retains the actual NPC target.
                let keys = quiz.buttons.map { GuideDatabase.answerKey($0.text) }
                let complete = database.questions.contains { q in
                    let known = Set(q.answers.values.flatMap { $0 }.map(GuideDatabase.answerKey))
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
        let badgeCenter = lines.first { $0.confidence >= 0.25 && $0.center.x > 0.48 && (0.66...0.82).contains($0.center.y) && database.badgeName(from: $0.text) != nil }?.center.y
        let wide = Double(image.width) / Double(image.height) > 0.52
        let centerY = wide ? badgeCenter.map { $0 - 0.091 * Double(image.width) / Double(image.height) } ?? 0.684 : 0.684
        return try PixelImage(image).heartScores(centerY: centerY)
    }
    private func textImage(_ image: CGImage, minimumWidth: Int) -> CGImage {
        guard image.width < minimumWidth else { return image }
        let height = Int(Double(minimumWidth) * Double(image.height) / Double(image.width))
        guard let context = CGContext(data: nil, width: minimumWidth, height: height, bitsPerComponent: 8, bytesPerRow: minimumWidth * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: minimumWidth, height: height))
        return context.makeImage() ?? image
    }
    private func regionLines(_ image: CGImage, region: UnitRect, words: [String]? = nil, minimumWidth: Int = 0) throws -> [TextBox] {
        guard let cropped = cropImage(image, rect: region) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
        request.recognitionLanguages = ["zh-Hans"]
        request.customWords = words ?? (Array(SceneClassifier.menuLabels) + Array(SceneClassifier.topicLabels)
            + database.questions.flatMap { $0.answers.values.flatMap { $0 } })
        try VNImageRequestHandler(cgImage: textImage(cropped, minimumWidth: minimumWidth), options: [:]).perform([request])
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
