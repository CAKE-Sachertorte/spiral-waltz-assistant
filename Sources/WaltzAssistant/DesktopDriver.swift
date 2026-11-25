import AppKit
import ScreenCaptureKit
import ApplicationServices
import WaltzCore

enum DriverError: LocalizedError {
    case screenPermission, accessibilityPermission, noWindow, changedWindow, lostFocus, emergency, invalidCalibration, skipMissing
    var errorDescription: String? {
        switch self {
        case .screenPermission: return "请先为「舞会助手」授予屏幕录制权限，再重新打开程序。"
        case .accessibilityPermission: return "请先在系统设置中为「舞会助手」开启辅助功能权限。"
        case .noWindow: return "没有找到所选来源的游戏窗口，请先打开客户端或 iPhone 镜像。"
        case .changedWindow: return "镜像窗口已移动、缩放或切换，已停止。请重新识别后再开始。"
        case .lostFocus: return "游戏窗口已失去焦点，已停止。"
        case .emergency: return "已触发左上角紧急停止。"
        case .invalidCalibration: return "游戏区域尚未校准，或比例不正确。请拖框圈住完整游戏画面。"
        case .skipMissing: return "没有在固定位置检测到跳过键，已停止。"
        }
    }
}

struct CapturedWindow {
    let image: CGImage
    let id: CGWindowID
    let frame: CGRect
    let pid: pid_t
}

@MainActor final class DesktopDriver {
    static let mirrorID = "com.apple.ScreenContinuity"
    var nativeClient = false
    private var targetID: String { nativeClient ? "com.baitian.szx.lxywq" : Self.mirrorID }
    static var screenAllowed: Bool { CGPreflightScreenCaptureAccess() }
    static var inputAllowed: Bool { AXIsProcessTrusted() }
    static func requestScreen() { _ = CGRequestScreenCaptureAccess() }
    static func requestInput() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    static func emergencyTriggered() -> Bool {
        guard let p = CGEvent(source: nil)?.location else { return false }
        return p.x >= 0 && p.x < 5 && p.y >= 0 && p.y < 5
    }
    func capture() async throws -> CapturedWindow {
        guard Self.screenAllowed else { throw DriverError.screenPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.filter({
            $0.owningApplication?.bundleIdentifier == targetID && $0.windowLayer == 0 && $0.isOnScreen
                && $0.frame.height > 400 && $0.frame.width > 180 && (nativeClient ? $0.frame.height / $0.frame.width > 0.9 : $0.frame.height / $0.frame.width > 1.65)
        }).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let app = window.owningApplication else { throw DriverError.noWindow }
        let config = SCStreamConfiguration()
        let scale = min(2.0, 1900 / window.frame.height)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        return CapturedWindow(image: image, id: window.windowID, frame: window.frame, pid: app.processID)
    }
    func activateMirror() {
        NSRunningApplication.runningApplications(withBundleIdentifier: targetID).first?.activate(options: [])
    }
    func click(_ p: UnitPoint, capture: CapturedWindow, crop: UnitRect) throws {
        guard Self.inputAllowed else { throw DriverError.accessibilityPermission }
        guard !Self.emergencyTriggered() else { throw DriverError.emergency }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == capture.pid else { throw DriverError.lostFocus }
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let info = infos.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == capture.id }),
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let current = CGRect(dictionaryRepresentation: bounds),
              abs(current.minX - capture.frame.minX) < 1, abs(current.minY - capture.frame.minY) < 1,
              abs(current.width - capture.frame.width) < 1, abs(current.height - capture.frame.height) < 1 else { throw DriverError.changedWindow }
        guard (0...1).contains(p.x), (0...1).contains(p.y), crop.valid else { throw DriverError.invalidCalibration }
        let gamePoint = nativeClient && p == Engine.skipPoint ? UnitPoint(x: p.x, y: 0.975) : p
        let point = CGPoint(x: current.minX + (crop.x + gamePoint.x * crop.width) * current.width,
                            y: current.minY + (crop.y + gamePoint.y * crop.height) * current.height)
        // A modal or another window may cover the captured window without changing its image.
        // Refuse to send a click unless the topmost normal window at this point is the target.
        let hit = infos.first { row in
            guard (row[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let raw = row[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: raw) else { return false }
            return rect.contains(point) && ((row[kCGWindowAlpha as String] as? Double) ?? 1) > 0.1
        }
        guard (hit?[kCGWindowNumber as String] as? NSNumber)?.uint32Value == capture.id else { throw DriverError.changedWindow }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        guard let down, let up else { throw DriverError.changedWindow }
        down.post(tap: .cghidEventTap)
        // Always release the mouse before returning, including when a stop key arrives.
        usleep(35_000)
        up.post(tap: .cghidEventTap)
    }
}
