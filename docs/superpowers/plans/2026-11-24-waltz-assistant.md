# 舞会助手 Implementation Plan

**Goal:** 交付完全本地、仅处理当前人物的 Mac 自动化工具。
**Architecture:** 纯状态机/攻略数据与 macOS 识别及点击驱动分开；默认仅观察模式。
**Tech Stack:** Swift 5.9 / SwiftUI / Vision / ScreenCaptureKit / CoreGraphics；不使用第三方依赖。
**Spec:** ../specs/2026-11-24-waltz-assistant-design.md

## Global Constraints

- macOS 14+，不调用 GPT 或网络 API。
- 只处理当前人物：满心→情报→可用问答→停止。
- 聊天/情报后使用最左侧跳过；确认结算点中央。
- 不自动找人、闲逛、跳舞、比美或购买；未知界面/切人立即停。

## 顺序执行

- [x] 攻略数据与纯决策：先写真实交互序列测试并确认缺少实现失败，再实现字符匹配、问答索引、阶段和停止逻辑。
- [x] 原生识别：从用户录屏抽取场景，验证 OCR、菜单布局和爱心识别；拒绝低置信度输入。
- [x] 窗口驱动与 UI：捕获仅限镜像窗口，校准矩形，窗口/人物锁、紧急停止、动作上限；仅观察默认开启。
- [x] 验证并打包：独立测试程序，录屏回放，release 编译、签名校验、原生窗口检查；写使用说明与验证记录。
