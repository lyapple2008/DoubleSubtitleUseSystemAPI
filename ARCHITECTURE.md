# DoubleSubtitle 项目架构与数据流程

## 1. 项目目标
DoubleSubtitle 是一个 iOS 双语字幕应用。
通过 Broadcast Upload Extension 捕获系统播放音频，统一转换为 `16kHz / 单声道 / Int16`，送入语音识别，再将识别片段翻译并在应用内（含 PiP 状态）展示原文与译文。

## 2. 模块构成

### 2.1 主 App（`DoubleSubtitle`）
- 入口
  - `DoubleSubtitle/App/DoubleSubtitleApp.swift`
- UI 层
  - `DoubleSubtitle/Views/ContentView.swift`
  - `DoubleSubtitle/Views/LanguageSelectorView.swift`
  - `DoubleSubtitle/Views/SubtitleDisplayView.swift`
- 模型层
  - `DoubleSubtitle/Models/SubtitleItem.swift`
  - `DoubleSubtitle/Models/LanguageOption.swift`
- 管理器
  - `DoubleSubtitle/Managers/AudioCaptureManager.swift`
  - `DoubleSubtitle/Managers/SpeechRecognitionManager.swift`
  - `DoubleSubtitle/Managers/TranslationManager.swift`
  - `DoubleSubtitle/Managers/SubtitleOverlayManager.swift`

### 2.2 Broadcast Extension（`AudioCaptureExtension`）
- 主处理器
  - `AudioCaptureExtension/AudioCaptureExtension.swift`
- 扩展类型
  - `com.apple.broadcast-services-upload`
  - `RPBroadcastProcessModeSampleBuffer`

### 2.3 共享能力（App Group）
- Group ID：`group.com.doublesubtitle.app`
- 用于主 App 与 Extension 之间的文件通信。

## 3. 各模块职责

### 3.1 `AudioCaptureExtension`：采集与格式归一化
- 仅处理 ReplayKit 的 `audioApp`（系统播放音频）。
- 从 `CMSampleBuffer/CMBlockBuffer` 读取原始 PCM。
- 兼容非连续 block buffer（必要时走 `CMBlockBufferCopyDataBytes`）。
- 使用 `AVAudioConverter` 将输入（常见 44.1k/48k、双声道、Float32/Int16）统一转换为 `16k/mono/Int16`。
- 将转换后字节追加写入共享文件 `captured_audio.pcm`。
- 通过 `broadcast_active` 文件通知广播开始/结束状态。

### 3.2 `AudioCaptureManager`：进程间数据读取与缓冲拼接
- 轮询 `broadcast_active` 判断用户是否已在系统弹窗中真正开始直播。
- 以 100ms 定时读取 `captured_audio.pcm` 新增字节。
- 处理奇数字节跨包问题（`pendingPCMByte`），确保 Int16 样本不被截断。
- 构造固定格式 `AVAudioPCMBuffer(16k/mono/int16)`，通过 delegate 传给识别模块。
- 同时落盘 `debug_recognition_audio.wav`（用于核对送识别前音频）。

### 3.3 `SpeechRecognitionManager`：语音识别
- 管理语音识别权限与 locale。
- 创建 `SFSpeechAudioBufferRecognitionRequest`。
- 接收外部 PCM buffer 并 `append` 到识别请求。
- 通过 delegate 输出 partial/final 文本结果。

### 3.4 `ContentViewModel`：编排、断句、翻译触发
- 负责编排采集/识别的生命周期。
- 管理字幕状态：
  - `currentSubtitle`：实时预览
  - `historySubtitles`：已提交历史
- 断句策略（多规则组合）：
  - 强标点立即断句
  - 弱标点按长度或超时断句
  - 长度上限兜底断句
  - 稳定度/静音兜底断句
- 每个已提交片段异步触发翻译。
- 翻译回写按 `subtitleID` 精确更新对应历史项。

### 3.5 `TranslationManager`：翻译
- 维护源语言/目标语言配置。
- iOS 26+ 走系统 `TranslationSession`。
- 低版本走占位翻译逻辑。
- 输出翻译链路日志（开始/成功/失败）。

### 3.6 展示层：`SubtitleDisplayView` 与 `SubtitleOverlayManager`
- 在主界面展示实时字幕与历史字幕。
- 历史记录当前为“最新在上”（按时间戳倒序）。
- `SubtitleOverlayManager` 负责 PiP 状态与字幕更新通道。

## 4. 数据契约（关键）

### 4.1 Extension -> App 音频数据
- 文件：`captured_audio.pcm`（App Group 容器内）
- 格式：小端 PCM Int16
- 规格：`16000 Hz / 1 channel / 16-bit signed`

### 4.2 Extension -> App 状态信号
- 文件：`broadcast_active`
- 语义：
  - 文件存在：广播已开始
  - 文件不存在：广播已结束

### 4.3 Debug 数据
- 文件：`debug_recognition_audio.wav`（App Documents）
- 语义：识别前最终输入音频的可视化/听感校验样本。

## 5. 端到端数据处理流程

1. 用户点击“开始识别”。
2. `ContentViewModel.startRecording`：
   - 请求语音识别权限
   - 设置各 manager 的 delegate
   - 启动等待广播状态
   - 触发隐藏的 `RPSystemBroadcastPickerView`
3. 用户在系统弹窗点击“开始直播”，Extension 启动。
4. Extension 写入 `broadcast_active`。
5. 主 App 轮询到 `broadcast_active`，开启文件监控。
6. Extension 持续把转换后的 `16k/mono/int16` 音频追加到 `captured_audio.pcm`。
7. 主 App 增量读取新字节，做样本对齐并封装成 `AVAudioPCMBuffer`。
8. `SpeechRecognitionManager` 接收 buffer 并输出 partial/final 识别文本。
9. `ContentViewModel` 执行断句，形成稳定片段并加入 `historySubtitles`。
10. 每个稳定片段触发异步翻译，结果回写同一条历史字幕。
11. UI 显示实时字幕与历史字幕（最新在上）。
12. 停止时 flush 未提交文本并清理定时器与识别状态。

## 6. 时序与并发点
- 文件读取定时器：100ms（`AudioCaptureManager`）
- 断句定时器：200ms（`ContentViewModel`）
- 翻译：按片段异步任务并发执行（`Task`）
- UI 更新：主线程回调，保证状态一致性。

## 7. 当前架构的关键设计点
- 在 Extension 侧先做统一格式转换，避免主 App 侧反复协商/转换格式。
- 以 App Group 文件做跨进程通信，简化 Extension 与主 App 生命周期解耦。
- 断句/翻译与采集链路分层，便于独立调优字幕实时性与稳定性。

## 8. 当前约束与注意事项
- 翻译系统 API 在代码中以 `iOS 26+` 分支启用，低版本是占位翻译。
- 文件轮询方案实现简单稳定，但不是最低延迟 IPC。
- PiP 目前主要承担状态控制与字幕数据通道，渲染层可继续增强。

## 9. 建议的后续演进方向
- 将文件轮询升级为更低延迟的数据通知机制。
- 增加识别前缓冲队列与背压策略，提升高负载下稳定性。
- 增强翻译调度（节流/批处理）以优化高语速场景。
- 建立结构化指标：采集延迟、识别延迟、翻译延迟、断句触发原因分布。
