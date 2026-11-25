import Foundation

public struct UnitPoint: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
public struct UnitRect: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var center: UnitPoint { UnitPoint(x: x + width / 2, y: y + height / 2) }
    public var valid: Bool { x >= 0 && y >= 0 && width > 0.1 && height > 0.1 && x + width <= 1.001 && y + height <= 1.001 }
}
public struct TextBox: Codable, Equatable {
    public var text: String
    public var confidence: Float
    public var rect: UnitRect
    public init(text: String, confidence: Float, rect: UnitRect) { self.text = text; self.confidence = confidence; self.rect = rect }
    public var center: UnitPoint { rect.center }
}
public enum Scene: String, Codable { case menu, topics, dialogue, answers, reward, eavesdrop, hub, finished, loading, danceScene, unknown, blocked }
public struct Observation: Codable {
    public var scene: Scene
    public var character: String?
    public var hearts: Int?
    public var buttons: [TextBox]
    public var text: String
    public var skipVisible: Bool
    public var heartScores: [Double]
    public var lines: [TextBox]
    public init(scene: Scene, character: String? = nil, hearts: Int? = nil, buttons: [TextBox] = [], text: String = "", skipVisible: Bool = false, heartScores: [Double] = [], lines: [TextBox] = []) {
        self.scene = scene; self.character = character; self.hearts = hearts; self.buttons = buttons
        self.text = text; self.skipVisible = skipVisible; self.heartScores = heartScores; self.lines = lines
    }
    public var fingerprint: String {
        // Reward confirmation always taps the center. Animated background text, item
        // labels and a fading continue hint must not keep resetting frame stability.
        if scene == .reward { return "reward" }
        if scene == .finished { return "finished" }
        if scene == .hub { return "hub:" + buttons.map { normalize($0.text) }.joined(separator: "|") }
        return [scene.rawValue, character ?? "", hearts.map(String.init) ?? "?", buttons.map { normalize($0.text) }.joined(separator: "|"), normalize(text)].joined(separator: ":")
    }
}
public struct Decision: Equatable {
    public enum Kind: String { case tap, tapAndSkip, wait, done, pause }
    public var kind: Kind
    public var point: UnitPoint?
    public var skipPoint: UnitPoint?
    public var message: String
    public init(_ kind: Kind, _ message: String, point: UnitPoint? = nil, skipPoint: UnitPoint? = nil) {
        self.kind = kind; self.message = message; self.point = point; self.skipPoint = skipPoint
    }
}
public func normalize(_ text: String) -> String {
    text.folding(options: [.widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_CN"))
        .filter { $0.isLetter || $0.isNumber }.lowercased()
        .replacingOccurrences(of: "她", with: "他").replacingOccurrences(of: "裳洛洛", with: "裘洛洛")
}
