import AppKit
import SwiftUI
import WaltzCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct WaltzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AssistantModel()
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some SwiftUI.Scene {
        WindowGroup("舞会助手") { ContentView(model: model).onDisappear { model.stop("窗口已关闭") } }
            .defaultSize(width: 920, height: 740)
            .windowResizability(.contentMinSize)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

private let rose = Color(red: 0.60, green: 0.31, blue: 0.43)

struct ContentView: View {
    @ObservedObject var model: AssistantModel
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "heart.circle.fill").font(.system(size: 34)).foregroundStyle(rose)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("舞会助手").font(.title2.weight(.semibold))
                        Text("当前人物 · 完全本地").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Picker("画面来源", selection: $model.nativeClient) {
                    Text("iPhone 镜像").tag(false)
                    Text("Mac 游戏客户端").tag(true)
                }.disabled(model.running || model.busy)
                HStack(spacing: 8) {
                    stat("人物", model.character)
                    stat("爱心", model.hearts)
                    stat("画面", model.scene)
                }
                Text(model.status).font(.system(size: 13, weight: .medium)).foregroundStyle(rose)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(12).background(rose.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                HStack {
                    Button { model.scan() } label: { Label("识别窗口", systemImage: "viewfinder") }
                        .disabled(model.running || model.busy)
                    Button { model.calibrating.toggle() } label: { Label("拖框校准", systemImage: "crop") }
                        .disabled(model.preview == nil || model.running || model.busy)
                    Button("常用窗口布局") { model.defaultCrop() }
                        .disabled(model.preview == nil || model.running || model.busy)
                }
                Text(model.calibrating ? "在右侧拖框圈住完整游戏画面，排除标题栏及左右边框。" : "先核对人物与爱心。框选区域仅用于这个镜像窗口，可重新校准。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle("仅观察，不点击游戏", isOn: $model.dryRun).disabled(model.running)
                Toggle("自动切人（完成后闲逛找下一位）", isOn: $model.autoSwitch).disabled(model.running)
                HStack(spacing: 10) {
                    Button { model.start() } label: {
                        Label(model.dryRun ? "演练当前人物" : "运行当前人物", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(rose).disabled(model.running || model.busy || model.crop == nil)
                    Button("暂停") { model.stop("已暂停，继续时将重新核对当前人物") }.disabled(!model.running)
                    Button("停止") { model.stop() }.keyboardShortcut("s", modifiers: [.control, .option])
                }
                Text("补满心 → 情报 → 可用问答 → 跳舞/比美 → 自动停止").font(.caption.weight(.medium))
                Text("开启「自动切人」后，完成全部任务会自动闲逛切换到下一位角色。\n不自动购买、换装或充值。未知画面停止。\n紧急停止：⌃⌥S，或把鼠标移到主屏幕左上角。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    permission("屏幕录制", model.screenAllowed, input: false)
                    permission("辅助功能", model.inputAllowed, input: true)
                    Spacer()
                    Button("刷新") { model.refreshPermissions() }.font(.caption)
                }
                Text("首次使用需在系统设置中允许本程序读取镜像和发送点击。授权后如仍未生效，请退出重开。")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("操作记录").font(.headline)
                    Spacer()
                    Button("打开记录") { model.openLogs() }.font(.caption)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { _, row in
                            Text(row).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(9)
                }.frame(minHeight: 100, maxHeight: .infinity).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                DisclosureGroup("识别详情") {
                    Text(model.diagnostic).font(.caption2)
                    ScrollView { Text(model.lastOCR).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90)
                }.font(.caption).foregroundStyle(.secondary)
                Text("攻略库：\(model.guideCount)位角色 · ©️森托瑞亚").font(.caption2).foregroundStyle(.tertiary)
            }.padding(22).frame(minWidth: 500, idealWidth: 530, maxWidth: 620)
            Divider()
            VStack(spacing: 10) {
                HStack { Text(model.calibrating ? "框选游戏区域" : "窗口预览").font(.headline); Spacer(); if model.running { ProgressView().controlSize(.small) } }
                CalibrationCanvas(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                Text(model.preview == nil ? "点击「识别窗口」后显示镜像预览" : "玫红色框是程序实际识别与点击的范围")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(18).frame(minWidth: 300, maxWidth: .infinity)
        }.frame(minWidth: 850, minHeight: 700).background(Color(nsColor: .windowBackgroundColor))
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
    private func permission(_ label: String, _ allowed: Bool, input: Bool) -> some View {
        Button { model.permission(input) } label: { Label(label, systemImage: allowed ? "checkmark.circle.fill" : "circle") }
            .font(.caption).foregroundStyle(allowed ? Color.green : Color.secondary).disabled(model.running)
    }
}

final class CalibrationSelection: ObservableObject { @Published var rect: CGRect? }
struct CalibrationCanvas: View {
    @ObservedObject var model: AssistantModel
    @StateObject private var selection = CalibrationSelection()
    var body: some View {
        GeometryReader { geo in
            if let image = model.preview {
                let size = image.size
                let scale = min(geo.size.width / max(1, size.width), geo.size.height / max(1, size.height))
                let displayed = CGSize(width: size.width * scale, height: size.height * scale)
                let origin = CGPoint(x: (geo.size.width - displayed.width) / 2, y: (geo.size.height - displayed.height) / 2)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image).resizable().frame(width: displayed.width, height: displayed.height).position(x: geo.size.width/2, y: geo.size.height/2)
                    if let r = selection.rect ?? model.crop.map({ CGRect(x: origin.x + $0.x * displayed.width, y: origin.y + $0.y * displayed.height, width: $0.width * displayed.width, height: $0.height * displayed.height) }) {
                        Rectangle().fill(rose.opacity(model.calibrating ? 0.12 : 0.025))
                            .overlay(Rectangle().stroke(rose, style: StrokeStyle(lineWidth: 2, dash: model.calibrating ? [5,3] : [])))
                            .frame(width:r.width, height:r.height).position(x:r.midX, y:r.midY).allowsHitTesting(false)
                    }
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 2).onChanged { value in
                    guard model.calibrating, !model.running else { return }
                    let a = clamp(value.startLocation, origin, displayed), b = clamp(value.location, origin, displayed)
                    selection.rect = CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
                }.onEnded { _ in
                    guard model.calibrating, let r = selection.rect else { return }
                    model.calibrate(UnitRect(x:(r.minX-origin.x)/displayed.width, y:(r.minY-origin.y)/displayed.height,
                                             width:r.width/displayed.width,height:r.height/displayed.height))
                    selection.rect = nil
                })
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "iphone.gen3").font(.system(size: 52)).foregroundStyle(.tertiary)
                    Text("等待镜像画面").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    private func clamp(_ p: CGPoint, _ origin: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x:max(origin.x,min(origin.x+size.width,p.x)),y:max(origin.y,min(origin.y+size.height,p.y)))
    }
}
