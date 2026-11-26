import Foundation
public enum HeartClassifier {
    public static func count(scores: [Double]) -> Int? {
        guard scores.count == 3 else { return nil }
        // Only count opaque (fully filled) hearts. Semi-transparent hearts blend
        // with the background and have low scores. 0 opaque hearts = 0/3.
        // This is more robust than trying to distinguish semi-transparent from empty.
        return scores.filter { $0 > 0.72 }.count
    }
}
public struct SceneClassifier {
    public static let menuLabels: Set<String> = ["和他聊聊", "一会儿再见", "打听情报", "好感度问答", "跳舞", "主动比美", "神秘商店"]
    public static func wanderFinished(_ text: String) -> Bool {
        let key = normalize(text)
        return key.contains("基本上都和大家见过了")
            || (key.contains("见过") && key.contains("碰运气偷听"))
            || (key.contains("想要和人聊天") && key.contains("似乎还是直接找"))
    }
    public let database: GuideDatabase
    public init(database: GuideDatabase) { self.database = database }
    public func classify(lines: [TextBox], heartScores: [Double], skip: Bool, wideLayout: Bool = false) -> Observation {
        // Vision returns 0.3 for correctly read Chinese game labels in the real recording.
        // Confidence is combined with exact known words, fixed regions and two stable frames.
        let visible = lines.filter { $0.confidence >= 0.25 }
        let text = visible.map(\.text).joined(separator: "\n")
        let key = normalize(text)
        let left = visible.filter { $0.center.x < 0.48 && (0.32...0.77).contains($0.center.y) }
        let labels = Set(left.map { normalize($0.text) })
        let protagonist = visible.contains { normalize($0.text) == "玛格达" && $0.center.x < 0.48 && (0.66...0.82).contains($0.center.y) }
        let npc = visible.filter { $0.center.x > 0.48 && (0.66...0.82).contains($0.center.y) }
            .compactMap { database.character(named: $0.text)?.name }.first
        let name = npc ?? (protagonist ? "玛格达" : nil)
        func make(_ scene: Scene, _ buttons: [TextBox] = []) -> Observation {
            Observation(scene: scene, character: name, hearts: HeartClassifier.count(scores: heartScores), buttons: buttons,
                        text: text, skipVisible: skip, heartScores: heartScores, lines: lines)
        }
        if ["连接已中断", "无法连接", "iphone正在使用", "重新连接", "请输入密码", "解锁iphone"].contains(where: { key.contains($0) }) {
            return make(.blocked)
        }
        if Self.wanderFinished(text) { return make(.finished) }
        let navigation = visible.filter { $0.center.x > 0.65 && (0.32...0.77).contains($0.center.y) }
        let navLabels = Set(navigation.map { normalize($0.text) })
        if navLabels.contains("闲逛") && !navLabels.isDisjoint(with: ["事件信息", "找人", "离开舞会"]) { return make(.hub, navigation) }
        if ["离开舞会", "事件信息", "找人", "商城", "服装商店"].contains(where: { labels.contains($0) }) { return make(.blocked) }
        let resultTitle = visible.contains {
            ["胜利", "失败"].contains(normalize($0.text)) && $0.rect.height > 0.035
                && (0.25...0.75).contains($0.center.y)
        }
        if key.contains("获得情报") || key.contains("好感度提升") || key.contains("点击屏幕继") || resultTitle { return make(.reward) }
        // Paired style rows identify a contest even when its names/skip text are absent.
        let styles: Set<String> = ["活泼", "成熟", "保暖", "清凉", "清纯", "性感", "可爱", "高贵", "华丽"]
        let styleRows = visible.filter {
            (0.05...0.28).contains($0.center.y) && ($0.center.x < 0.20 || $0.center.x > 0.80)
                && styles.contains(normalize($0.text))
        }
        if !key.contains("任务信息") && Set(styleRows.map { normalize($0.text) }).count >= 3 { return make(.danceScene) }
        let eventOptions = visible.filter {
            $0.center.x > 0.70 && (0.32...0.77).contains($0.center.y)
                && $0.rect.width < 0.43 && (1...10).contains(normalize($0.text).count)
                && database.character(named: $0.text) == nil
                && !["跳过", "返回"].contains(normalize($0.text))
        }.sorted { $0.center.y < $1.center.y }
        if protagonist && eventOptions.count == 2
            && eventOptions[1].center.y - eventOptions[0].center.y > 0.04 {
            return make(.eavesdrop, eventOptions)
        }
        let decline = visible.filter { normalize($0.text) == "不偷听" && (0.32...0.77).contains($0.center.y) && $0.rect.width < 0.45 }
        if !decline.isEmpty { return make(.eavesdrop, decline) }
        if labels.contains("和他聊聊") || labels.intersection(Self.menuLabels).count >= 2 { return make(.menu, left + visible.filter { normalize($0.text) == "跳过" && (0.48...0.64).contains($0.center.x) && (0.32...0.77).contains($0.center.y) }) }
        let topics = Set(["军事", "风物", "冒险", "人际", "艺术", "时尚", "娱乐", "商业", "政治", "神秘"])
        if (labels.contains("返回") && !labels.isDisjoint(with: topics)) || labels.intersection(topics).count >= 2 { return make(.topics, left) }
        // Only buttons in the known answer bands. Never turn an arbitrary paragraph into a choice.
        let choices = visible.filter {
            ((wideLayout ? 0.30 : 0.39)...0.72).contains($0.center.y) && ($0.center.x < 0.38 || $0.center.x > 0.70)
                && normalize($0.text) != "玛格达" && database.character(named: $0.text) == nil
                && $0.rect.width < 0.43 && (1...10).contains(normalize($0.text).count)
                && !["返回", "跳过", "跳舞", "主动比美", "打听情报", "好感度问答", "神秘商店", "和他聊聊", "一会儿再见"].contains(normalize($0.text))
        }.sorted { $0.center.y < $1.center.y }
        if (3...4).contains(choices.count) { return make(.answers, choices) }
        // Prefer the actual competition skip button over the dialogue heuristic.
        let danceSkip = visible.contains { normalize($0.text) == "跳过" && $0.center.x > 0.70 && $0.center.y > 0.70 }
        if key.contains("总分") || danceSkip { return make(.danceScene) }
        if key.contains("任务信息") && visible.contains(where: { $0.center.y > 0.78 && $0.center.y < 0.94 }) { return make(.dialogue) }
        if !key.contains("任务信息") && (key.contains("舞会") || key.contains("加载")) { return make(.loading) }
        return make(.unknown)
    }
}
