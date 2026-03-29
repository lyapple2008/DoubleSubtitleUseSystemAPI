# DoubleSubtitle 项目总结文档

## 1. 项目概要

DoubleSubtitle 是一款 iOS 端双语字幕应用，通过捕获系统播放音频进行实时语音识别和翻译，在画中画（Picture-in-Picture）中显示双语字幕。

### 解决的问题

- 用户在 iOS 设备上观看视频或聆听音频时，无法直接获取语音内容的文字形式
- 对于学习外语、听力障碍人士或在嘈杂环境中需要字幕辅助的用户，提供实时双语字幕显示

### 使用场景

- 观看外文视频时获取实时翻译字幕
- 学习外语时对照原文和译文
- 会议或演讲中记录和翻译语音内容
- 在无法开启声音的场景下通过文字了解音频内容

### 核心能力

- **系统音频捕获**：通过 iOS ReplayKit 的 Broadcast Upload Extension 捕获系统播放音频，无需麦克风权限
- **实时语音识别**：调用系统 SFSpeechRecognizer API 进行流式语音识别
- **智能翻译**：调用系统 Translation API（iOS 26+）进行翻译
- **双语显示**：在主界面和画中画中同时显示原文和译文

---

## 2. 技术框架

### 2.1 项目模块组成

项目由以下主要模块组成：

| 模块 | 路径 | 职责 |
|------|------|------|
| 系统播放音频捕获模块 | `AudioCaptureExtension/` | 通过 Broadcast Upload Extension 捕获系统播放音频，统一转换为 16kHz/单声道/Int16 格式 |
| 音频读取模块 | `DoubleSubtitle/Managers/AudioCaptureManager.swift` | 进程间数据读取与缓冲拼接，轮询共享文件获取音频数据 |
| 语音识别模块 | `DoubleSubtitle/Managers/SpeechRecognitionManager.swift` | 调用系统语音识别 API 进行流式识别 |
| 断句模块 | `DoubleSubtitle/Managers/SentenceSegmenter.swift` | 将流式识别结果智能断句为稳定片段 |
| 翻译模块 | `DoubleSubtitle/Managers/TranslationManager.swift` | 调用系统翻译 API 进行翻译 |
| 字幕显示模块 | `DoubleSubtitle/Views/SubtitleDisplayView.swift` | 主界面字幕展示 |
| 画中画管理模块 | `DoubleSubtitle/Managers/SubtitleOverlayManager.swift` | 画中画状态控制与字幕更新通道 |
| 视图模型 | `DoubleSubtitle/Views/ContentView.swift` | 编排采集/识别生命周期，管理字幕状态 |

### 2.2 iOS 系统语音识别和翻译功能的用法

#### 2.2.1 系统语音识别（SFSpeechRecognizer）

项目使用 iOS 系统框架 `Speech` 进行语音识别，核心用法如下：

**权限请求**：
```swift
SFSpeechRecognizer.requestAuthorization { status in
    // status == .authorized 时表示授权成功
}
```

**创建识别器**：
```swift
let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
```

**创建流式识别请求**：
```swift
let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
recognitionRequest.shouldReportPartialResults = true
if #available(iOS 16, *) {
    recognitionRequest.addsPunctuation = true  // 自动添加标点
    recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
}
```

**输入音频数据**：
```swift
// 接收外部传入的 PCM 音频 buffer
recognitionRequest.append(audioBuffer)
```

**接收识别结果**：
```swift
let recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
    let text = result.bestTranscription.formattedString  // 识别文本
    let isFinal = result.isFinal  // 是否为最终结果
}
```

**音频格式要求**：
- 系统期望的音频格式通过 `recognitionRequest.nativeAudioFormat` 获取
- 项目中将所有音频统一转换为 16kHz/单声道/Int16 格式以确保兼容性

#### 2.2.2 系统翻译（Translation Framework）

项目使用 iOS 系统框架 `Translation` 进行翻译（iOS 26+），核心用法如下：

**配置源语言和目标语言**：
```swift
let sourceLanguageCode = Locale.Language(identifier: sourceLanguage.code)
let targetLanguageCode = Locale.Language(identifier: targetLanguage.code)
```

**创建翻译会话并执行翻译**：
```swift
let session = TranslationSession(
    installedSource: sourceLanguageCode,
    target: targetLanguageCode
)
let response = try await session.translate(text)
let translatedText = response.targetText
```

**版本兼容性**：
- iOS 26+ 使用系统 Translation API
- 低版本使用占位翻译逻辑（`[翻译: xxx]`）

### 2.3 流式识别中字幕显示与翻译流程

#### 2.3.1 字幕显示机制

项目采用**分层显示**策略，区分当前实时预览字幕和历史稳定字幕：

**实时预览字幕（currentSubtitle）**：
- 显示当前正在识别、尚未稳定的文本
- 颜色为橙色，表示内容可能还会变化
- 通过 `refreshCurrentSubtitlePreview` 函数实时更新

**历史稳定字幕（historySubtitles）**：
- 已完成识别的稳定片段，按时间戳倒序显示
- 原文和译文同时显示
- 翻译完成后更新显示

**UI 显示逻辑**（`SubtitleDisplayView.swift`）：
```swift
// 当前字幕 - 实时预览
Text(currentOriginalText)
    .foregroundColor(currentSubtitle ? .orange : .secondary)

// 历史记录 - 稳定字幕
ForEach(historyByNewestFirst) { item in
    Text(item.originalText)  // 原文
    Text(item.translatedText)  // 译文
}
```

#### 2.3.2 断句策略

项目实现了多规则组合的断句策略（`SentenceSegmenter.swift`）：

1. **强标点断句**：检测到句号、逗号、问号、感叹号等立即断句
2. **长度断句**：文本长度超过 `maxSentenceLength`（默认30字符）时断句
3. **停顿断句**：超过 `pauseThreshold`（默认1.5秒）无新文本时断句
4. **强制flush**：识别结束时强制提交剩余文本

**断句处理流程**：
```swift
func processResult(_ text: String) -> [SegmentedSentence] {
    // 1. 计算稳定前缀（与上一帧的公共部分）
    let stablePrefix = longestCommonPrefix(lastResult, text)

    // 2. 从非稳定部分提取句子
    while let sentence = extractSentence(from: uncommittedStable) {
        segments.append(sentence)  // 添加到待翻译队列
    }

    // 3. 更新状态
    lastResult = text
    return segments
}
```

#### 2.3.3 翻译流程

翻译采用**异步队列**机制，确保不阻塞识别主流程：

**翻译任务入队**：
```swift
private func enqueueTranslation(subtitleID: UUID, text: String) {
    translationQueue.append(TranslationJob(
        subtitleID: subtitleID,
        text: text,
        sessionID: translationSessionID
    ))
    processNextTranslationIfNeeded()
}
```

**翻译结果回写**：
```swift
private func updateTranslatedSubtitle(subtitleID: UUID, translatedText: String) {
    // 1. 更新历史字幕数据
    if let index = historySubtitles.lastIndex(where: { $0.id == subtitleID }) {
        historySubtitles[index] = updated
    }
    // 2. 同步到画中画显示
    subtitleOverlayManager.updateSubtitle(updated)
}
```

**翻译状态显示**：
- 刚提交的字幕显示 "翻译中..."
- 翻译成功后更新为实际译文
- 翻译失败时显示 "翻译失败"

#### 2.3.4 端到端数据流程

```
用户点击「开始识别」
    ↓
触发 RPSystemBroadcastPickerView
    ↓
用户在系统弹窗点击「开始直播」
    ↓
AudioCaptureExtension 开始写入音频数据
    ↓
AudioCaptureManager 轮询读取音频文件
    ↓
SpeechRecognitionManager 接收 PCM buffer 进行识别
    ↓
SentenceSegmenter 处理识别结果，进行断句
    ↓
断句产生的稳定片段加入 historySubtitles
    ↓
每个片段触发异步翻译任务
    ↓
翻译结果回写到对应历史字幕
    ↓
UI 实时更新显示原文和译文
```

### 2.4 画中画字幕显示

画中画（Picture-in-Picture）功能允许用户在观看第三方音视频内容时，同步看到双语字幕。项目使用 `AVPictureInPictureController` 实现画中画功能。

#### 2.4.1 画中画初始化

**检查设备支持**：
```swift
guard AVPictureInPictureController.isPictureInPictureSupported() else {
    isPiPPossible = false
    return
}
```

**创建画中画内容源**：
项目使用视频通话模式的画中画（`AVPictureInPictureVideoCallViewController`），因为系统音频捕获场景与视频通话类似：
```swift
let contentController = AVPictureInPictureVideoCallViewController()
contentController.view.backgroundColor = .black

// 使用 UIHostingController 嵌入 SwiftUI 字幕视图
let hostingController = UIHostingController(rootView: PiPSubtitleOverlayView(overlayManager: self))
contentController.addChild(hostingController)
contentController.view.addSubview(hostingController.view)

// 创建内容源
let contentSource = AVPictureInPictureController.ContentSource(
    activeVideoCallSourceView: sourceView,
    contentViewController: contentController
)
let controller = AVPictureInPictureController(contentSource: contentSource)
```

#### 2.4.2 画中画字幕布局

画中画视图使用 SwiftUI 实现，分为上下两部分：

- **上半部分**：显示当前识别的原文
- **下半部分**：显示当前翻译结果

```swift
var body: some View {
    GeometryReader { proxy in
        VStack(spacing: 8) {
            PiPSubtitlePanel(text: originalText)  // 上半部分：原文
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PiPSubtitlePanel(text: translatedText)  // 下半部分：译文
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .background(Color.black.opacity(0.86))
    }
}
```

**字幕面板样式**：
- 白色文字，15号字体，中等字重
- 半透明黑色背景（`Color.white.opacity(0.08)`）
- 圆角10pt
- 支持自动滚动到最新内容

#### 2.4.3 自动启动画中画

项目支持在应用进入后台时自动启动画中画，方便用户切换到其他应用查看字幕：

```swift
// 启用自动启动
func setAutomaticPiPStartFromInlineEnabled(_ enabled: Bool) {
    allowsAutomaticPiPStartFromInline = enabled
    pipController?.canStartPictureInPictureAutomaticallyFromInline = enabled
}
```

**自动启动时机**：
- 用户点击「开始识别」后，设置 `shouldAutoStartPiPOnBackground = true`
- 应用进入后台（`didEnterBackground`）时，如果正在识别则自动启动画中画

#### 2.4.4 字幕数据同步

画中画字幕通过 `SubtitleOverlayManager` 进行管理，与主界面字幕保持同步：

**更新原文**：
```swift
func updateCurrentOriginalText(_ text: String) {
    currentOriginalText = text
}
```

**更新译文**：
```swift
func updateCurrentTranslatedText(_ text: String) {
    currentTranslatedText = text
}
```

**翻译结果回写时同步到画中画**：
```swift
private func updateTranslatedSubtitle(subtitleID: UUID, translatedText: String) {
    // 更新历史字幕数据
    if let index = historySubtitles.lastIndex(where: { $0.id == subtitleID }) {
        historySubtitles[index] = updated
    }
    // 同步到画中画显示
    subtitleOverlayManager.updateSubtitle(updated)
}
```

#### 2.4.5 画中画生命周期管理

**启动画中画**：
```swift
func startPiP() {
    guard let pipController = pipController, isPiPPossible else { return }
    pipController.startPictureInPicture()
}
```

**停止画中画**：
```swift
func stopPiP() {
    guard let pipController = pipController else { return }
    pipController.stopPictureInPicture()
}
```

**清理画中画**（识别结束时调用）：
```swift
func teardownPiP() {
    allowsAutomaticPiPStartFromInline = false
    if let pipController = pipController {
        pipController.canStartPictureInPictureAutomaticallyFromInline = false
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        }
    }
    pipController = nil
    pipSourceView = nil
}
```

---

## 3. 技术特点

### 3.1 进程间通信

- 使用 **App Group** 共享数据：`group.com.doublesubtitle.app`
- Extension 写入 `captured_audio.pcm` 文件
- 主 App 增量读取文件内容
- 通过 `broadcast_active` 文件状态通知广播开始/结束

### 3.2 音频格式统一

- Extension 侧使用 `AVAudioConverter` 将各种格式转换为统一的 16kHz/单声道/Int16
- 简化主 App 侧的音频处理逻辑

### 3.3 高内聚低耦合

- 每个模块（Manager）职责单一，通过 Delegate 模式与 ViewModel 通信
- 断句逻辑与识别逻辑分离
- 翻译任务与识别任务解耦

---

## 4. 注意事项

- 翻译功能需要 iOS 26+ 系统支持，低版本显示占位翻译
- 语音识别支持离线识别（on-device recognition），可提升响应速度
- 项目使用 SwiftUI 进行 UI 开发
- 画中画功能在后台时自动启用，前台时可手动切换
