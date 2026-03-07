# ContentView.swift 代码详解

这是一份面向 Swift/iOS 开发小白的完整指南。

---

## 一、文件整体结构

```
ContentView.swift 包含两部分：
├── 1. ContentView (SwiftUI 视图) - 第 1-115 行
└── 2. ContentViewModel (业务逻辑) - 第 117-540 行
```

---

## 二、导入的框架

```swift
import SwiftUI      // Apple 的现代 UI 框架
import AVFoundation // 音视频处理
import ReplayKit    // 屏幕录制/系统音频捕获
import UIKit        // iOS UI 框架（用于后台通知等）
import Combine      // 响应式编程框架
```

---

## 三、SwiftUI 基础语法

### 1. `@State` - 视图内部状态

```swift
@State private var triggerSystemPicker = false
```
- `private` - 私有属性
- `@State` - SwiftUI 专用的属性包装器，表示"视图内部可变的临时状态"
- 当值改变时，SwiftUI 会自动重新渲染视图

### 2. `@StateObject` - 视图模型（重点！）

```swift
@StateObject private var viewModel = ContentViewModel()
```
- 创建 ViewModel 实例
- **关键区别**：
  - `@State` - 用于简单数据类型（String, Bool, Int）
  - `@StateObject` - 用于 class 类型的 ViewModel

### 3. `$` 绑定语法

```swift
LanguageSelectorView(
    sourceLanguage: $viewModel.sourceLanguage,  // $ 符号创建双向绑定
    targetLanguage: $viewModel.targetLanguage
)
```
- `$viewModel.sourceLanguage` - 传递**引用**而非值
- 当子视图修改值时，父视图的 viewModel 也会更新

### 4. `.onReceive` - 接收外部事件

```swift
.onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
    viewModel.handleDidEnterBackground()
}
```
- 监听系统通知（如进入后台、进入前台）
- 当应用进入后台时，自动调用 `handleDidEnterBackground()`

---

## 四、SwiftUI 视图结构

### `some View` 返回类型

```swift
var body: some View {
    // body 必须返回一个遵循 View 协议的类型
    VStack(spacing: 0) {
        // ... 内容
    }
}
```

### 常见布局容器

| 容器 | 作用 |
|------|------|
| `VStack` | 垂直排列（vertical） |
| `HStack` | 水平排列（horizontal） |
| `ZStack` | 叠加排列（z-axis） |
| `Spacer()` | 占据剩余空间 |

### 修饰器链

```swift
Button(action: {...}) {
    Text("开始识别")
        .font(.headline)           // 字体
        .frame(maxWidth: .infinity) // 宽度
        .padding()                  // 内边距
        .background(Color.blue)    // 背景色
        .foregroundColor(.white)   // 文字颜色
        .cornerRadius(12)         // 圆角
}
```

---

## 五、ViewModel 部分

### `@Published` - 发布属性（配合 ObservableObject）

```swift
@Published var sourceLanguage: LanguageOption = .defaultSource
```
- 当值改变时，自动通知所有观察者（SwiftUI 视图）
- 类似于 Android 的 LiveData

### `@Published` + `didSet` - 值变化监听

```swift
@Published var sourceLanguage: LanguageOption = .defaultSource {
    didSet {
        // 当 sourceLanguage 值改变时，自动执行这里
        TranslationManager.shared.configure(source: sourceLanguage, target: targetLanguage)
    }
}
```
- `didSet` 是属性观察器
- 值改变后自动执行回调

### `@MainActor` - 主线程执行

```swift
@MainActor
final class ContentViewModel: NSObject, ObservableObject {
```
- 保证所有成员都在主线程执行
- UI 更新必须在主线程

### `NSObject` 继承

```swift
class ContentViewModel: NSObject, ObservableObject
```
- 继承 `NSObject` 是为了使用 `Timer` 和其他 Objective-C 兼容功能

---

## 六、关键 Swift 语法

### 1. 闭包（Closure）

```swift
Button(action: {
    viewModel.startRecording {
        triggerSystemPicker = true
    }
}) { ... }
```
- `action: { ... }` - 点击时执行的代码块
- `viewModel.startRecording { ... }` - 回调闭包参数

### 2. `@escaping` - 逃逸闭包

```swift
func startRecording(onReadyToShowPicker: @escaping () -> Void)
```
- 闭包可能在函数返回后才执行
- 需要用 `@escaping` 标记

### 3. `[weak self]` - 避免循环引用

```swift
Task { [weak self] in
    guard let self = self else { return }
    // 使用 self
}
```
- 防止内存泄漏（闭包持有 self，self 不持有闭包）

### 4. `Task { @MainActor in }` - 并发处理

```swift
Task { @MainActor in
    self.performPrepareAndShowPicker(...)
}
```
- 异步执行代码
- `@MainActor` 确保在主线程更新 UI

### 5. Protocol 协议

```swift
extension ContentViewModel: AudioCaptureDelegate {
    nonisolated func audioCaptureDidStart() { ... }
}
```
- 类似 Java 的接口
- `nonisolated` - 允许在非主线程调用

### 6. 可选类型（Optional）

```swift
@Published var currentSubtitle: SubtitleItem?  // ? 表示可选
```
- `?` - 值可以是 `nil`
- 使用 `?.` 或 `if let` 解包

### 7. `guard` - 条件守卫

```swift
guard granted else {
    // 权限未授予时执行
    Task { @MainActor in
        self?.showError(message: "需要语音识别权限")
    }
    return  // 提前退出函数
}
```
- 条件不满足时执行 else 分支并提前返回
- 类似于 if-else，但更简洁，强制要求 return

### 8. Combine 订阅（响应式编程）

```swift
subtitleOverlayManager.$isPiPActive      // $ 前缀获取 Publisher
    .receive(on: RunLoop.main)          // 切换到主线程
    .sink { [weak self] active in       // 订阅变化
        self?.isPiPActive = active      // 同步到自己的属性
    }
    .store(in: &cancellables)           // 保存订阅（防止被释放）
```
- `$` 前缀将 `@Published` 属性转换为 Publisher
- `.receive(on:)` 指定接收线程
- `.sink { }` 订阅并处理变化
- `.store(in:)` 保存订阅，防止被释放

### 9. `??` - 空值合并运算符

```swift
let text = item.translatedText ?? "默认值"
```
- 如果左边为 nil，返回右边的默认值

---

## 七、startRecording 函数详解（第 175-187 行）

### 原始代码

```swift
func startRecording(onReadyToShowPicker: @escaping () -> Void) {
    requestPermissions { [weak self] granted in
        guard granted else {
            Task { @MainActor in
                self?.showError(message: "需要语音识别权限")
            }
            return
        }
        Task { @MainActor in
            self?.performPrepareAndShowPicker(onReadyToShowPicker: onReadyToShowPicker)
        }
    }
}
```

### 执行流程图

```
用户点击「开始识别」按钮
           │
           ▼
┌──────────────────────────────┐
│  startRecording() 被调用      │
│  传入闭包 onReadyToShowPicker │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│  requestPermissions()        │
│  请求语音识别权限              │
└──────────────┬───────────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
  权限已授予        权限被拒绝
       │               │
       ▼               ▼
┌──────────────┐  ┌────────────────────┐
│ Task {       │  │ Task {             │
│   @MainActor │  │   @MainActor       │
│   self?.     │  │   self?.showError   │
│   perform... │  │ }                  │
│ }            │  └────────────────────┘
└──────────────┘
       │
       ▼
┌──────────────────────────────────┐
│  performPrepareAndShowPicker()    │
│  1. 重置 sentenceSegmenter        │
│  2. 清空历史记录                  │
│  3. 设置本次会话起始索引           │
│  4. 配置 delegate                 │
│  5. 配置语音识别器语言             │
│  6. 启动等待广播开始               │
│  7. 执行 onReadyToShowPicker()   │
│     (触发系统弹窗)                │
└──────────────────────────────────┘
```

---

## 八、数据流图示

```
┌─────────────────────────────────────────────────────────────┐
│                        ContentView                          │
│  ┌─────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │ Language    │  │ SubtitleDisplay  │  │ Buttons       │  │
│  │ Selector    │  │ View              │  │               │  │
│  └──────┬──────┘  └────────┬─────────┘  └───────┬───────┘  │
│         │                  │                     │          │
│         └──────────────────┼─────────────────────┘          │
│                            │                                  │
│                     ┌──────▼──────┐                          │
│                     │ @StateObject │                          │
│                     │ viewModel    │                          │
│                     └──────┬──────┘                          │
└────────────────────────────┼────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │  Audio     │  │ Speech      │  │ Translation │
    │  Capture   │  │ Recognition │  │ Manager     │
    │  Manager   │  │ Manager     │  │             │
    └─────────────┘  └─────────────┘  └─────────────┘
```

---

## 九、handleRecognitionResultText 函数详解（第 381-395 行）

### 函数作用

这个函数是整个**字幕分段显示的核心逻辑**。当语音识别返回结果时，它负责：
1. 将识别文本交给 `SpeechSentenceSegmenter` 进行智能断句
2. 提交已确定的句子段落（触发翻译）
3. 更新当前预览字幕（显示未确认部分）

### 整体流程图

```
语音识别结果
     ↓
┌─────────────────────────────────────────┐
│ 1. sentenceSegmenter.processResult()    │
│    - 找出稳定前缀（最长公共前缀）        │
│    - 提取已确定的句子（标点/长度断句）  │
│    - 更新已提交文本 committedText       │
└─────────────────────────────────────────┘
     ↓
┌─────────────────────────────────────────┐
│ 2. submitRecognizedSegments()           │
│    - 提交确定段落 → 加入历史字幕 + 翻译 │
│    - 过滤无效内容（纯标点/过短/重复）  │
└─────────────────────────────────────────┘
     ↓
     ┌─────────────────────────────────────┐
     │ 3a. isFinal = true（最终结果）        │
     │     - 强制 flush 剩余文本            │
     │     - 重置 segmenter                  │
     │     - 清空当前预览                   │
     └─────────────────────────────────────┘
     │
     │ 3b. isFinal = false（中间结果）
     │     - refreshCurrentSubtitlePreview()
     │     - 显示未提交的文本为预览字幕
     └─────────────────────────────────────┘
```

### 关键变量说明

| 变量 | 作用 |
|------|------|
| `sentenceSegmenter` | `SpeechSentenceSegmenter` 实例，负责流式文本断句 |
| `sentenceFlushTimer` | 定时器（0.3秒），定期检测静默超时并刷新分段 |
| `currentSessionHistoryStartIndex` | 本次识别的字幕起始索引，用于区分历史 |
| `recentCommittedSegments` | 最近提交的段落记录，用于去重 |
| `translationQueue` | 翻译任务队列，按顺序执行翻译 |
| `currentSubtitle` | 当前显示的**预览字幕**（未确认，可能变化） |
| `historySubtitles` | 已提交的**历史字幕**列表（已确认，稳定） |

### 翻译队列机制

```swift
// 1. 加入翻译队列
private func enqueueTranslation(subtitleID: UUID, text: String) {
    translationQueue.append(TranslationJob(subtitleID: subtitleID, text: text))
    processNextTranslationIfNeeded()
}

// 2. 顺序处理翻译（避免并发冲突）
private func processNextTranslationIfNeeded() {
    guard !isTranslationQueueRunning else { return }  // 已有任务运行中
    guard !translationQueue.isEmpty else { return }    // 队列为空

    isTranslationQueueRunning = true
    let job = translationQueue.removeFirst()           // 取下一个任务

    Task {
        let translatedText = try await TranslationManager.shared.translate(job.text)
        await MainActor.run {
            // 更新翻译结果
            self.updateTranslatedSubtitle(...)
            self.isTranslationQueueRunning = false
            self.processNextTranslationIfNeeded()       // 继续处理下一个
        }
    }
}
```

### SpeechSentenceSegmenter 断句策略

```swift
// 断句优先级（从高到低）：
// 1. 标点断句 - 遇到标点符号（，。！？；,.!?;）立即断句
// 2. 长度断句 - 超过 maxSentenceLength（默认30字）强制断句
// 3. 停顿断句 - 超过 pauseThreshold（默认1.5秒）无新文本时断句
```

### 后台进入处理

```swift
func handleDidEnterBackground() {
    guard isRecording else { return }           // 正在识别中
    guard !subtitleOverlayManager.isActive else { return }  // PiP 未启动
    startPiP()                                    // 自动启动画中画
}
```

---

## 十、总结

| 概念 | 说明 |
|------|------|
| `@State` | 视图内部状态 |
| `@Published` | ViewModel 的可观察属性 |
| `@StateObject` | 创建 ViewModel 实例 |
| `$` 绑定 | 双向数据绑定 |
| `some View` | SwiftUI 返回类型 |
| `@escaping` | 逃逸闭包 |
| `[weak self]` | 防止循环引用 |
| `Task { }` | 异步并发 |
| `Combine` | 响应式编程框架 |
| `.sink { }` | 订阅 Publisher |
| `.store(in:)` | 保存订阅，防止释放 |
| `didSet` | 属性观察器 |
| `??` | 空值合并运算符 |
