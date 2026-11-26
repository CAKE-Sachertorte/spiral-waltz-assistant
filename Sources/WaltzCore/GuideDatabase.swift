import Foundation

public struct CharacterGuide: Codable {
    public var name: String
    public var aliases: [String]
    public var topics: [String]
    public var codes: [Int]
}
public struct QuestionGuide: Codable {
    public var name: String
    public var group: Int
    public var answers: [String: [String]]
}
public struct QuizAnswer {
    public var index: Int
    public var question: String
}
public struct GuideDatabase: Codable {
    public var source: String
    public var sha256: String
    public var characters: [CharacterGuide]
    public var questions: [QuestionGuide]
    public static func bundled() throws -> GuideDatabase {
        // SwiftPM's generated accessor assumes a sibling bundle. A distributable .app
        // loads its own Resources first, so it never depends on the build directory.
        let appResource = Bundle.main.url(forResource: "guide", withExtension: "json")
        guard let url = appResource ?? Bundle.module.url(forResource: "guide", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(GuideDatabase.self, from: Data(contentsOf: url))
    }
    public func character(named text: String) -> CharacterGuide? {
        let key = normalize(text).replacingOccurrences(of: "巴代伦卡", with: "巴伐伦卡")
            .replacingOccurrences(of: "玛菲利娅", with: "玛菲利亚")
        if let exact = characters.first(where: { ([ $0.name ] + $0.aliases).contains { normalize($0) == key } }) { return exact }
        // Only the name badge is supplied here. Permit a family suffix, never arbitrary prose.
        return characters.sorted { $0.name.count > $1.name.count }.first {
            let n = normalize($0.name)
            return n.count >= 1 && key.hasPrefix(n) && key.count <= n.count + 6
        }
    }
    public func answer(character: String, text: String, options: [String]) -> QuizAnswer? {
        guard let person = self.character(named: character), (3...4).contains(options.count) else { return nil }
        let optionKeys = options.map(Self.answerKey)
        // Build the character's accepted texts from the existing authoritative question data.
        // A unique visible match needs neither a recognized stem nor the original order.
        var accepted: [String: [String]] = [:]
        for q in questions where person.codes.indices.contains(q.group) {
            for answer in q.answers[String(person.codes[q.group])] ?? [] {
                accepted[Self.answerKey(answer), default: []].append(q.name)
            }
        }
        let hits = optionKeys.indices.filter { accepted[optionKeys[$0]] != nil }
        if hits.count == 1, let index = hits.first {
            return QuizAnswer(index: index, question: accepted[optionKeys[index]]!.joined(separator: " / "))
        }
        let body = normalize(text)
        let synonyms: [String: [String]] = [
            "无限金钱": ["用不完", "无尽", "无限金钱", "无限的金币"],
            "妈妈意见不合": ["妈妈意见", "母亲意见", "妈妈发生争执"],
            "杀人医生": ["医生"], "性格": ["品质", "性格"],
            "欧灵参政": ["欧灵参政", "欧灵参与", "欧灵进入议会"],
            "警备队扩张": ["警备队扩张", "扩大警备队"],
            "贫民窟暴动": ["贫民窟暴动", "平民窟暴动"],
            "贵族平民通婚": ["贵族平民通婚", "贵族和平民", "平民与贵族"],
            "法律是什么": ["法律是什么", "法律究竟", "法律是"],
            "破城以后": ["破城", "城市被攻破"],
            "朋友被害": ["朋友被害", "朋友被杀"],
            "善行回报": ["善行回报", "善行的回报", "好人好报"],
            "慈善事业": ["慈善"], "欧灵不听话": ["欧灵不听话"],
            "包办婚姻": ["包办婚姻"], "血腥玛丽": ["血腥玛丽"]
        ]
        var candidates: [(QuestionGuide, Int)] = []
        for question in questions {
            let allKnown = Set(question.answers.values.flatMap { $0 }.map(Self.answerKey))
            let overlap = optionKeys.filter { allKnown.contains($0) }.count
            let terms = [question.name] + (synonyms[question.name] ?? [])
            let explicit = terms.contains { body.contains(normalize($0)) }
            if overlap >= 2 || explicit { candidates.append((question, overlap + (explicit ? 5 : 0))) }
        }
        guard let bestScore = candidates.map({ $0.1 }).max(), bestScore >= 2 else { return nil }
        let best = candidates.filter { $0.1 == bestScore }
        var results: [QuizAnswer] = []
        for (q, _) in best {
            guard person.codes.indices.contains(q.group) else { continue }
            let ordinal = person.codes[q.group] - 1
            guard options.indices.contains(ordinal) else { continue }
            if let known = q.answers[String(ordinal + 1)] {
                let matches = optionKeys.enumerated().filter { known.map(Self.answerKey).contains($0.element) }
                guard matches.count == 1 else { continue }
                results.append(QuizAnswer(index: matches[0].offset, question: q.name))
            }
        }
        guard let first = results.first, results.allSatisfy({ $0.index == first.index }) else { return nil }
        return first
    }
    private static func answerKey(_ text: String) -> String {
        var key = normalize(text)
        for (long, short) in [("黑色", "黑"), ("蓝色", "蓝"), ("绿色", "绿"), ("红色", "红"), ("报复", "复仇"), ("防御结界", "防御"), ("隐形魔法", "隐形"), ("隐身魔法", "隐形"), ("真有效吗", "真的有效吗"), ("结构问题", "体制问题")] {
            if key == long { key = short }
        }
        return key
    }
}
