import AppKit
import Combine
import WaltzCore

struct Calibration: Codable {
    var rect: UnitRect
    var windowAspect: Double
}

@MainActor final class AssistantModel: ObservableObject {
    @Published var status = "先识别窗口，再拖框校准游戏区域"
    @Published var character = "尚未识别"
    @Published var hearts = "—"
    @Published var scene = "—"
    @Published var preview: NSImage?
    @Published var gamePreview: NSImage?
    @Published var running = false
    @Published var busy = false
    @Published var calibrating = false
    @Published var dryRun = true
    @Published var autoSwitch = false
    @Published var nativeClient = UserDefaults.standard.bool(forKey: "nativeClient") {
        didSet {
            stop("画面来源已切换，请重新识别并校准")
            driver.nativeClient = nativeClient
            UserDefaults.standard.set(nativeClient, forKey: "nativeClient")
            calibration = nil; crop = nil; preview = nil; latestCapture = nil
            if let saved = UserDefaults.standard.data(forKey: calibrationKey), let c = try? JSONDecoder().decode(Calibration.self, from: saved) { calibration = c; crop = c.rect }
        }
    }
    private var calibrationKey: String { nativeClient ? "gameCalibration.nativeClient" : "gameCalibration" }
    @Published var logs: [String] = []
    @Published var crop: UnitRect?
    @Published var screenAllowed = DesktopDriver.screenAllowed
    @Published var inputAllowed = DesktopDriver.inputAllowed
    @Published var lastOCR = ""
    @Published var diagnostic = ""
    private let database: GuideDatabase
    private let reader: VisionReader
    private let driver = DesktopDriver()
    private var calibration: Calibration?
    private var latestCapture: CapturedWindow?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var globalKey: Any?
    private var localKey: Any?
    private var logURL: URL?

    init() {
        database = try! GuideDatabase.bundled()
        reader = VisionReader(database: database)
        driver.nativeClient = nativeClient
        if let saved = UserDefaults.standard.data(forKey: calibrationKey), let c = try? JSONDecoder().decode(Calibration.self, from: saved) {
            calibration = c; crop = c.rect
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WaltzAssistant")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        logURL = folder.appendingPathComponent("operations.log")
        globalKey = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.control, .option]) && event.keyCode == 1 {
                Task { @MainActor in self?.stop("快捷键停止") }
            }
        }
        localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.control, .option]) && event.keyCode == 1 {
                Task { @MainActor in self?.stop("快捷键停止") }; return nil
            }
            return event
        }
        log("就绪：53位角色，22类题目；仅观察模式已开启")
    }
    var guideCount: Int { database.characters.count }
    func refreshPermissions() { screenAllowed = DesktopDriver.screenAllowed; inputAllowed = DesktopDriver.inputAllowed }
    func permission(_ input: Bool) {
        stop("等待系统权限")
        if input { DesktopDriver.requestInput() } else { DesktopDriver.requestScreen() }
        refreshPermissions()
    }
    func log(_ message: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        let row = "\(formatter.string(from: Date()))  \(message)"
        logs.append(row)
        if logs.count > 160 { logs.removeFirst(logs.count - 160) }
        if let url = logURL, let bytes = (row + "\n").data(using: .utf8) {
            if !FileManager.default.fileExists(atPath: url.path) { try? bytes.write(to: url) }
            else if let handle = try? FileHandle(forWritingTo: url) { defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: bytes) }
        }
    }
    func stop(_ reason: String = "已停止") {
        generation = UUID(); task?.cancel(); task = nil
        running = false; busy = false; status = reason; log(reason)
    }
    func calibrate(_ rect: UnitRect) {
        guard !running, let capture = latestCapture, rect.valid,
              (0.42...(nativeClient ? 0.62 : 0.51)).contains(rect.width * Double(capture.image.width) / (rect.height * Double(capture.image.height))) else {
            status = "选框应为完整竖屏游戏画面，请排除标题栏和左右边框"; return
        }
        let c = Calibration(rect: rect, windowAspect: capture.frame.width / capture.frame.height)
        calibration = c; crop = rect; calibrating = false
        if let data = try? JSONEncoder().encode(c) { UserDefaults.standard.set(data, forKey: calibrationKey) }
        status = "校准已保存，请再点一次「识别窗口」核对人物与爱心"; log(status)
    }
    func defaultCrop() {
        // Standard Apple iPhone Mirroring window: excludes the toolbar and rounded border.
        calibrate(nativeClient ? UnitRect(x: 0.122, y: 0.036, width: 0.755, height: 0.964) : UnitRect(x: 0.0195, y: 0.0423, width: 0.961, height: 0.949))
    }
    func scan() {
        guard !running, !busy else { return }
        busy = true; refreshPermissions()
        task = Task {
            defer { busy = false }
            do {
                let captured = try await driver.capture()
                guard !Task.isCancelled else { return }
                latestCapture = captured; preview = NSImage(cgImage: captured.image, size: .zero)
                guard let image = try gameImage(captured) else {
                    calibrating = true; status = "已读取镜像窗口。拖框圈住完整游戏画面，排除顶部镜像工具栏。"; return
                }
                let observation = try await read(image)
                guard !Task.isCancelled else { return }
                show(observation, image: image)
                var engine = Engine(database: database)
                let decision = engine.next(observation)
                status = "预览：\(decision.message)"; log(status)
            } catch { status = error.localizedDescription; log(status) }
        }
    }
    private func gameImage(_ capture: CapturedWindow) throws -> CGImage? {
        guard let calibration else { return nil }
        guard abs(capture.frame.width / capture.frame.height - calibration.windowAspect) < 0.012 else { throw DriverError.changedWindow }
        guard let image = cropImage(capture.image, rect: calibration.rect), image.height > 400,
              (0.42...(nativeClient ? 0.62 : 0.51)).contains(Double(image.width) / Double(image.height)) else { throw DriverError.invalidCalibration }
        return image
    }
    private func read(_ image: CGImage, preferOptions: Bool = true, preferHub: Bool = false) async throws -> Observation {
        let reader = self.reader
        return try await Task.detached(priority: .userInitiated) { try reader.read(image, preferOptions: preferOptions, preferHub: preferHub) }.value
    }
    private func show(_ observation: Observation, image: CGImage, rememberedCharacter: String? = nil) {
        gamePreview = NSImage(cgImage: image, size: .zero)
        character = observation.character == "玛格达" && rememberedCharacter != nil
            ? "\(rememberedCharacter!)（玛格达发言）" : observation.character ?? "对白中 / 尚未识别"
        hearts = observation.character == "玛格达" ? "—" : observation.hearts.map { "\($0) / 3" } ?? "不确定"
        scene = observation.scene.rawValue
        lastOCR = observation.text
        diagnostic = "红色覆盖率：" + observation.heartScores.map { String(format: "%.2f", $0) }.joined(separator: " / ")
    }
    func start() {
        guard !running, !busy, calibration != nil else { status = "请先识别并校准游戏区域"; return }
        refreshPermissions()
        guard screenAllowed else { status = DriverError.screenPermission.localizedDescription; return }
        guard dryRun || inputAllowed else { status = DriverError.accessibilityPermission.localizedDescription; return }
        let token = UUID(); generation = token; running = true; calibrating = false
        if !dryRun { driver.activateMirror() }
        status = dryRun ? "仅观察：正在识别，不发送点击" : "运行中：请让 游戏窗口保持前台"
        log(status)
        task = Task { await loop(token) }
    }
    private func loop(_ token: UUID) async {
        var engine = Engine(database: database)
        engine.autoSwitch = autoSwitch
        var previous = "", stable = 0, waits = 0, actionCount = 0, repeatCount = 0
        var lastAction = "", lastActionAt = Date.distantPast
        let began = Date()
        let maxActions = autoSwitch ? 200 : 80
        let maxTime = autoSwitch ? 1800.0 : 480.0
        var windowID: CGWindowID?
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            while generation == token && !Task.isCancelled {
                if DesktopDriver.emergencyTriggered() { throw DriverError.emergency }
                if actionCount >= maxActions || Date().timeIntervalSince(began) > maxTime { stop("达到单次运行上限，已停止"); return }
                let captured = try await driver.capture()
                guard generation == token, !Task.isCancelled else { return }
                if let windowID, windowID != captured.id { throw DriverError.changedWindow }
                windowID = captured.id
                guard let image = try gameImage(captured) else { throw DriverError.invalidCalibration }
                let observation = try await read(image, preferOptions: engine.quizActive, preferHub: engine.isSwitching)
                guard generation == token, !Task.isCancelled else { return }
                latestCapture = captured; preview = NSImage(cgImage: captured.image, size: .zero); show(observation, image: image, rememberedCharacter: engine.lockedCharacter)
                let fp = observation.fingerprint
                stable = fp == previous ? stable + 1 : 1
                previous = fp
                let competitionFrame = observation.scene == .danceScene || (engine.competitionActive && observation.scene == .unknown)
                if stable < ((competitionFrame || observation.scene == .hub || observation.scene == .finished) ? 1 : 2) { try await Task.sleep(nanoseconds: 650_000_000); continue }
                if (competitionFrame || fp == lastAction) && Date().timeIntervalSince(lastActionAt) < (competitionFrame ? 3.0 : 2.4) { try await Task.sleep(nanoseconds: 650_000_000); continue }
                let decision = engine.next(observation)
                status = decision.message
                if decision.kind == .wait {
                    waits += 1
                    let maxWaits = engine.isSwitching ? 30 : 12
                    if waits >= maxWaits { stop("连续无法可靠识别，已停止。请查看预览或重新校准。"); return }
                } else {
                    waits = 0; log(decision.message)
                    if decision.kind == .done || decision.kind == .pause { stop(decision.message); return }
                    if dryRun { stop("仅观察：\(decision.message)；未发送点击"); return }
                    if fp == lastAction { repeatCount += 1 } else { repeatCount = 0 }
                    if repeatCount >= decision.maximumIdenticalTaps && !competitionFrame { stop("点击后界面没有变化，已停止"); return }
                    guard let point = decision.point, let crop = calibration?.rect else { throw DriverError.invalidCalibration }
                    guard generation == token, !Task.isCancelled else { return }
                    try driver.click(point, capture: captured, crop: crop); actionCount += 1
                    lastAction = fp; lastActionAt = Date()
                    if decision.kind == .tapAndSkip, let skip = decision.skipPoint {
                        // No OCR or GPT call between the topic/intelligence click and skip.
                        var found = false
                        for _ in 0..<5 {
                            try await Task.sleep(nanoseconds: 320_000_000)
                            guard generation == token, !Task.isCancelled else { return }
                            let between = try await driver.capture()
                            guard generation == token, !Task.isCancelled else { return }
                            guard between.id == captured.id, between.frame == captured.frame else { throw DriverError.changedWindow }
                            guard let game = try gameImage(between) else { throw DriverError.invalidCalibration }
                            if try PixelImage(game).skipVisible() {
                                try driver.click(skip, capture: between, crop: crop); actionCount += 1; found = true; break
                            }
                        }
                        if !found { throw DriverError.skipMissing }
                    }
                }
                try await Task.sleep(nanoseconds: 700_000_000)
            }
        } catch is CancellationError { return }
        catch { if generation == token { stop(error.localizedDescription) } }
    }
    func openLogs() {
        if let logURL { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }
    }
}
