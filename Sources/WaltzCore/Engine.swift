import Foundation

public struct Engine {
    public static let skipPoint = UnitPoint(x: 0.22, y: 0.961)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public private(set) var lockedCharacter: String?
    public var autoSwitch: Bool = false
    public var isSwitching: Bool { phase == .switching || phase == .encounter }
    public var competitionActive: Bool { [.dance, .danceScene, .danceDialogue, .beauty, .beautyScene, .beautyDialogue, .encounter].contains(phase) }
    public let database: GuideDatabase
    private enum Phase { case ready, chat, intelligence, quiz, dance, danceScene, danceDialogue, beauty, beautyScene, beautyDialogue, switching, encounter }
    private var phase: Phase = .ready
    private var chats = 0
    private var rerolls = 0
    private var answers = 0
    private var danced = false
    private var beautied = false
    public var quizActive: Bool { phase == .quiz }
    public init(database: GuideDatabase) { self.database = database }
    public mutating func next(_ o: Observation) -> Decision {
        if o.scene == .finished || SceneClassifier.wanderFinished(o.text) {
            return Decision(.done, "已与所有人见面，没有新人物，停止")
        }
        // These recognized screens are safe entry points; no previous task is required.
        if o.scene == .reward {
            let contestResult = normalize(o.text).contains("查看攻略") || o.lines.contains {
                ["胜利", "失败"].contains(normalize($0.text)) && $0.rect.height > 0.035
                    && (0.25...0.75).contains($0.center.y)
            }
            if contestResult && !competitionActive { phase = .encounter }
            if phase == .danceScene { phase = .danceDialogue }
            if phase == .beautyScene { phase = .beautyDialogue }
            let hint = o.lines.first {
                $0.confidence >= 0.25 && normalize($0.text).contains("点击屏幕继")
                    && (0.25...0.92).contains($0.center.y)
            }
            var confirmation = Decision(.tap, hint == nil ? "确认结算，点屏幕中央" : "点击继续提示，确认结算", point: hint?.center ?? Self.center)
            confirmation.maximumIdenticalTaps = 6
            return confirmation
        }
        // Wandering can enter a contest against another player without a known NPC.
        // Preserve the old task identity; the next NPC menu is confirmed after the contest.
        if o.scene == .danceScene {
            if !competitionActive { phase = .encounter }
            if let skip = o.lines.first(where: { $0.confidence >= 0.25 && normalize($0.text) == "跳过" && $0.center.x > 0.70 && $0.center.y > 0.70 }) {
                return Decision(.tap, "点击识别到的跳过按钮", point: skip.center)
            }
            return Decision(.tap, "等待比赛动画结束，间隔点屏幕中央", point: Self.center)
        }
        if o.scene == .unknown && competitionActive {
            return Decision(.tap, "等待比赛动画结束，间隔点屏幕中央", point: Self.center)
        }
        if o.scene == .eavesdrop {
            let choices = o.buttons.sorted { $0.center.y < $1.center.y }
            // A quiz can temporarily expose only two choices while OCR is incomplete.
            if phase == .quiz && !choices.contains(where: { ["不偷听", "不关我事"].contains(normalize($0.text)) }) {
                return Decision(.wait, "问答选项未完整识别，等待重读")
            }
            let decline = choices.count == 2 ? choices[1] : choices.first { normalize($0.text) == "不偷听" }
            guard let decline else {
                return Decision(.wait, "等待不偷听选项")
            }
            return Decision(.tap, "选择下方选项，不偷听", point: decline.center)
        }
        if o.scene == .hub {
            guard let wander = o.buttons.first(where: { normalize($0.text) == "闲逛" }) else { return Decision(.wait, "等待闲逛按钮") }
            phase = .switching
            return Decision(.tap, "点击闲逛，检索下一个人", point: wander.center)
        }
        // Other NPCs may speak after dance/beauty; advance speech without replacing the task target.
        if o.scene == .dialogue {
            if (phase == .chat || phase == .intelligence) && o.skipVisible {
                return Decision(.tap, "点击最左侧跳过键", point: Self.skipPoint)
            }

            return Decision(.tap, "推进对白，点屏幕中央", point: Self.center)
        }
        if o.scene == .menu, let name = o.character, GuideDatabase.decliningChatNames.contains(name) {
            guard let bye = o.buttons.first(where: { normalize($0.text) == "一会儿再见" }) else {
                return Decision(.wait, "等待一会儿再见按钮")
            }
            phase = .switching
            return Decision(.tap, "\(name)：不接受聊天，点击一会儿再见", point: bye.center)
        }
        // During switching, skip character-change and blocked checks
        if !isSwitching {
            if let person = o.character, person != "玛格达", let lockedCharacter, person != lockedCharacter {
                return Decision(.pause, "人物从\(lockedCharacter)切换为\(person)，已停止")
            }
            if o.scene == .blocked { return Decision(.pause, "当前界面不属于满心、情报或问答流程") }
        }
        if isSwitching && lockedCharacter == nil && (o.scene == .unknown || o.scene == .loading) {
            return Decision(.wait, "检索动画中，等待")
        }
        if lockedCharacter == nil {
            let resumeQuiz = o.scene == .answers && o.hearts == 3
            guard o.scene == .menu || resumeQuiz, let name = o.character, database.character(named: name) != nil else {
                return Decision(.wait, "请停在人物互动菜单，或铭牌和满心清晰的问答页")
            }
            lockedCharacter = name
            if resumeQuiz { phase = .quiz }
        }
        // Auto-switch: new character's menu appeared — update locked character, reset state
        if isSwitching && o.scene == .menu {
            if let newName = o.character, newName != "玛格达" {
                guard database.character(named: newName) != nil else {
                    return Decision(.pause, "新人物\(newName)不在攻略库中，已停止")
                }
                lockedCharacter = newName
                chats = 0; answers = 0; danced = false; beautied = false; rerolls = 0
                phase = .ready
            }
        }
        guard let name = lockedCharacter, let guide = database.character(named: name) else { return Decision(.pause, "攻略库没有此人物") }
        func tap(_ b: TextBox, _ message: String, skip: Bool = false) -> Decision {
            Decision(skip ? .tapAndSkip : .tap, message, point: b.center, skipPoint: skip ? Self.skipPoint : nil)
        }
        func find(_ label: String) -> TextBox? { o.buttons.first { normalize($0.text) == normalize(label) } }
        func findLine(_ label: String) -> TextBox? {
            o.lines.filter { $0.confidence >= 0.25 }.first { normalize($0.text) == normalize(label) }
        }
        // Before scene switch: handle switching-phase special buttons and stop conditions
        if isSwitching {
            // Eavesdrop event: choose "不偷听" (the lower option)
            if let noEavesdrop = findLine("不偷听") {
                return Decision(.tap, "选择不偷听", point: noEavesdrop.center)
            }
            // Ball hub menu: click 闲逛 regardless of scene classification
            if let wander = findLine("闲逛") {
                return Decision(.tap, "点击闲逛，检索下一个人", point: wander.center)
            }
        }
        switch o.scene {
        case .menu:
            guard o.character == name else { return Decision(.wait, "当前铭牌未可靠识别，等待确认人物") }
            guard let hearts = o.hearts else { return Decision(.wait, "爱心识别不确定，请检查校准") }
            // Post-dance/beauty: menu reappeared after dance or beauty dialogue
            if phase == .danceDialogue || phase == .beautyDialogue {
                phase = .ready
                // Don't stop — fall through to check if more actions remain (auto-switch)
            }
            phase = .ready
            if hearts < 3 {
                guard chats < 25 else { return Decision(.pause, "聊天已达25次上限，请人工检查") }
                guard let chat = find("和他聊聊") else { return Decision(.pause, "未满心，但没有聊天按钮") }
                chats += 1; phase = .chat
                return tap(chat, "\(name)：\(hearts)/3心，打开聊天")
            }
            if let intel = find("打听情报") {
                phase = .intelligence
                return tap(intel, "\(name)：打听情报并跳过", skip: true)
            }
            if let quiz = find("好感度问答") {
                guard answers < 5 else { return Decision(.pause, "问答次数异常，已停止") }
                phase = .quiz
                return tap(quiz, "\(name)：开始好感度问答")
            }
            // Dance/Beauty contest: last priority, both optional, order not fixed.
            // Pick the topmost available action that hasn't been done yet.
            let optionalActions = o.buttons.filter { b in
                (normalize(b.text) == "跳舞" && !danced) || (normalize(b.text) == "主动比美" && !beautied)
            }.sorted { $0.center.y < $1.center.y }
            if let action = optionalActions.first {
                if normalize(action.text) == "跳舞" {
                    guard let skip = find("跳过") else { return Decision(.wait, "等待识别跳舞旁的跳过按钮") }
                    danced = true; phase = .dance
                    return tap(skip, "\(name)：跳过跳舞动画")
                } else {
                    beautied = true; phase = .beauty
                    return tap(action, "\(name)：主动比美")
                }
            }
            // All tasks done — auto-switch to next character if enabled
            if autoSwitch {
                if let bye = find("一会儿再见") {
                    phase = .switching
                    return tap(bye, "\(name)：全部完成，点击一会儿再见后闲逛")
                }
                return Decision(.done, "\(name)：全部完成，但没有一会儿再见按钮")
            }
            return Decision(.done, "\(name)：三颗心已满，情报、问答、跳舞和比美已处理，停止")
        case .topics:
            guard phase == .chat else { return Decision(.pause, "聊天阶段与画面不一致") }
            if let topic = o.buttons.first(where: { b in guide.topics.contains { normalize($0) == normalize(b.text) } }) {
                rerolls = 0
                return tap(topic, "\(name)：聊\(topic.text)，直接跳过", skip: true)
            }
            guard rerolls < 8, let back = find("返回") else { return Decision(.pause, "连续没有偏好话题，停止等待人工处理") }
            rerolls += 1
            return tap(back, "没有偏好话题，返回刷新")
        case .answers:
            guard phase == .quiz else { return Decision(.pause, "出现未发起的问答，不自动选择") }
            guard o.character == name || o.character == "玛格达" else { return Decision(.wait, "问答铭牌未可靠识别，等待确认人物") }
            let options = o.buttons.sorted { $0.center.y < $1.center.y }
            guard let answer = database.answer(character: name, text: o.text, options: options.map(\.text)) else {
                return Decision(.pause, "\(name)的答案未匹配：\(options.map(\.text).joined(separator: " / "))；已停止")
            }
            answers += 1
            return tap(options[answer.index], "\(answer.question)：选第\(answer.index + 1)项「\(options[answer.index].text)」")
        case .danceScene:
            return Decision(.wait, "等待比赛画面更新") // Handled before NPC identity checks.
        case .reward, .eavesdrop, .hub, .finished:
            // Handled above, including when starting without a remembered NPC.
            return Decision(.wait, "等待界面更新")
        case .dialogue:
            if phase == .chat || phase == .intelligence, o.skipVisible {
                return Decision(.tap, "点击最左侧跳过键", point: Self.skipPoint)
            }
            if isSwitching {
                return Decision(.tap, "推进对白，点屏幕中央", point: Self.center)
            }
            if phase == .dance || phase == .danceDialogue || phase == .beauty || phase == .beautyDialogue {
                return Decision(.tap, "推进对白，点屏幕中央", point: Self.center)
            }
            return Decision(.tap, "推进对白，点屏幕中央", point: Self.center)
        case .loading:
            return Decision(.wait, "等待加载完成")
        case .unknown:
            if isSwitching {
                return Decision(.wait, "检索动画中，等待")
            }
            return Decision(.wait, "等待可识别的稳定画面")
        case .blocked:
            // During switching: ball hub menu with 闲逛/找人/离开舞会 buttons
            if isSwitching {
                if let wander = findLine("闲逛") {
                    return Decision(.tap, "点击闲逛，检索下一个人", point: wander.center)
                }
                return Decision(.wait, "等待闲逛按钮出现")
            }
            return Decision(.pause, "不支持的界面")
        }
    }
}
