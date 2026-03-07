# SpeechRecognitionManager.swift 代码介绍

这是一份面向 Swift/iOS 开发小白的完整指南。

---

## 一、导入的框架

```swift
import Foundation
import Speech      // 系统语音识别框架
import AVFoundation // 音视频处理框架
```

- **Foundation**: iOS 基础框架，提供基础数据类型和工具
- **Speech**: 系统语音识别框架 (`SFSpeechRecognizer`)
- **AVFoundation**: 音视频处理框架，用于处理音频数据

---

## 二、iOS 系统语音识别功能介绍

### 1. SFSpeechRecognizer - 语音识别器

```swift
private var speechRecognizer: SFSpeechRecognizer?

// 创建语音识别器（指定语言）
speechRecognizer = SFSpeechRecognizer(locale: locale)
```

- `SFSpeechRecognizer` 是 iOS 系统的语音识别器类
- 可以指定语言（如 `zh-CN`、`en-US`）
- 需要检查是否可用：`speechRecognizer.isAvailable`

### 2. 离线识别（On-Device Recognition）

```swift
// 检查是否支持离线识别
func supportsOnDeviceRecognition(for locale: Locale) -> Bool {
    guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
    return recognizer.supportsOnDeviceRecognition
}

// 配置离线识别（iOS 16+）
if #available(iOS 16, *) {
    recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
}
```

| 特性 | 说明 |
|------|------|
| **离线识别** | 不需要网络，直接在设备上识别（更隐私、更快） |
| **在线识别** | 需要网络，识别效果通常更好 |
| **supportsOnDeviceRecognition** | 检查该语言是否支持离线识别 |

### 3. 标点符号自动添加（iOS 16+）

```swift
if #available(iOS 16, *) {
    recognitionRequest.addsPunctuation = true
}
```

- iOS 16+ 支持自动添加标点符号
- 识别结果会包含 `。` `，` `？` 等标点

### 4. 识别请求类型

```swift
// 创建识别请求（从外部音频缓冲区）
recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

// 设置实时返回部分结果
recognitionRequest.shouldReportPartialResults = true
```

- `shouldReportPartialResults = true`: 实时返回识别中的文本
- `addsPunctuation = true`: 自动添加标点（iOS 16+）
- `requiresOnDeviceRecognition`: 是否使用离线识别（iOS 16+）

---

## 三、Swift 语法基础

### 1. 协议 (Protocol)

```swift
protocol SpeechRecognitionDelegate: AnyObject {
    func speechRecognitionDidStart()
    func speechRecognitionDidStop()
    func speechRecognitionDidReceiveResult(_ result: String, isFinal: Bool)
    func speechRecognitionDidFail(with error: Error)
}
```

- `protocol` 是 Swift 的协议，类似于其他语言的"接口"
- `AnyObject` 表示这个协议只能被类实现（class-only protocol）
- 这是一个"委托模式" - 当语音识别发生各种事件时，通过 delegate 通知其他代码

### 2. 单例模式

```swift
final class SpeechRecognitionManager: NSObject {
    static let shared = SpeechRecognitionManager()  // 全局唯一实例
    ...
}
```

- `final`: 防止被继承
- `NSObject`: 继承自 Foundation 的基类
- `static let shared`: **单例模式** - 全局只有一个实例

### 3. 可选类型 (Optional)

```swift
private var speechRecognizer: SFSpeechRecognizer?  // 可能为 nil
private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
```

- 带有 `?` 表示**可选类型**
- 使用时需要解包：`speechRecognizer?.isAvailable`

### 4. 计算属性 (Computed Property)

```swift
var isAvailable: Bool {
    speechRecognizer?.isAvailable ?? false  // 空值合并运算符
}
```

- 每次访问时动态计算返回值
- `??` 是**空值合并运算符**，如果左边是 nil，返回右边的默认值

### 5. @escaping - 逃逸闭包

```swift
func requestPermission(completion: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async {
            completion(status == .authorized)
        }
    }
}
```

- `@escaping` 表示闭包可以"逃逸" - 函数返回后闭包仍可被调用
- `DispatchQueue.main.async` 切换回主线程

### 6. 委托模式

```swift
weak var delegate: SpeechRecognitionDelegate?

// 调用 delegate
delegate?.speechRecognitionDidReceiveResult(text, isFinal: isFinal)
```

- 使用 `weak` 避免循环引用
- `delegate?` 表示可选调用（如果 delegate 为 nil 则不调用）

---

## 四、核心方法详解

### 1. 请求权限

```swift
func requestPermission(completion: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async {
            completion(status == .authorized)
        }
    }
}
```

### 2. 配置语言

```swift
func configure(locale: Locale) {
    currentLocale = locale
    speechRecognizer = SFSpeechRecognizer(locale: locale)
    speechRecognizer?.delegate = self  // 设置代理监听可用性变化
}
```

### 3. 启动识别

```swift
func startRecognition() {
    // 1. 检查是否已在识别
    guard !_isRecognizing else { return }

    // 2. 确保语音识别器已创建
    if speechRecognizer == nil {
        speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
    }

    // 3. 检查是否可用
    guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
        delegate?.speechRecognitionDidFail(with: SpeechRecognitionError.notAvailable)
        return
    }

    // 4. 取消之前的任务
    recognitionTask?.cancel()

    // 5. 创建识别请求
    recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

    // 6. 配置识别选项
    recognitionRequest.shouldReportPartialResults = true
    if #available(iOS 16, *) {
        recognitionRequest.addsPunctuation = true
        recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
    }

    // 7. 启动识别任务
    recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
        // 处理识别结果...
    }

    _isRecognizing = true
}
```

### 4. 处理音频数据

```swift
func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard isRecognizing, let recognitionRequest = recognitionRequest else { return }
    // 将音频数据发送给识别引擎
    recognitionRequest.append(buffer)
}
```

### 5. 停止识别

```swift
func stopRecognition() {
    guard isRecognizing else { return }

    recognitionRequest?.endAudio()  // 通知识别结束
    recognitionTask?.cancel()       // 取消任务

    recognitionRequest = nil
    recognitionTask = nil
    _isRecognizing = false

    delegate?.speechRecognitionDidStop()
}
```

---

## 五、识别流程图

```
┌─────────────────────────────────────────────────────────────────────┐
│                    语音识别流程                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. requestPermission()                                            │
│     └─→ 请求语音识别权限                                            │
│                                                                     │
│  2. configure(locale:)                                              │
│     └─→ 配置识别语言（如 zh-CN、en-US）                             │
│                                                                     │
│  3. startRecognition()                                              │
│     ├─→ 检查识别器可用性                                           │
│     ├─→ 创建 SFSpeechAudioBufferRecognitionRequest                │
│     ├─→ 配置 shouldReportPartialResults = true                    │
│     ├─→ 配置 addsPunctuation（iOS 16+）                          │
│     ├─→ 配置 requiresOnDeviceRecognition（iOS 16+）              │
│     └─→ 启动 recognitionTask                                      │
│                                                                     │
│  4. processAudioBuffer(buffer) ←── 循环调用                        │
│     └─→ 将音频数据发送给识别引擎                                    │
│                                                                     │
│  5. delegate 回调                                                   │
│     ├─→ speechRecognitionDidStart()     ← 识别开始                │
│     ├─→ speechRecognitionDidReceiveResult() ← 实时返回结果          │
│     │      - isFinal = false: 中间结果（可能变化）                  │
│     │      - isFinal = true: 最终结果                              │
│     └─→ speechRecognitionDidStop()      ← 识别结束                │
│                                                                     │
│  6. stopRecognition()                                               │
│     └─→ 停止识别，释放资源                                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 六、SFSpeechRecognizerDelegate 代理

```swift
extension SpeechRecognitionManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                         availabilityDidChange available: Bool) {
        // 语音识别器可用性变化时调用
        if !available && isRecognizing {
            stopRecognition()
            delegate?.speechRecognitionDidFail(with: SpeechRecognitionError.notAvailable)
        }
    }
}
```

---

## 七、错误处理

```swift
enum SpeechRecognitionError: LocalizedError {
    case notAvailable           // 语音识别不可用
    case permissionDenied       // 权限被拒绝
    case requestCreationFailed  // 创建请求失败

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Speech recognition is not available"
        case .permissionDenied:
            return "Speech recognition permission was denied"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        }
    }
}
```

---

## 八、关键技术点总结

| 概念 | 说明 |
|------|------|
| `SFSpeechRecognizer` | iOS 系统语音识别器 |
| `SFSpeechAudioBufferRecognitionRequest` | 音频缓冲区识别请求 |
| `supportsOnDeviceRecognition` | 是否支持离线识别 |
| `addsPunctuation` | 自动添加标点（iOS 16+） |
| `shouldReportPartialResults` | 实时返回部分结果 |
| `static let shared` | 单例模式 |
| `@escaping` | 闭包逃逸 |
| `weak var delegate` | 委托模式（弱引用） |
| `??` | 空值合并运算符 |

---

## 九、iOS 语音识别使用注意事项

1. **权限申请** - 需要在 Info.plist 中配置 `NSSpeechRecognitionUsageDescription`
2. **设备支持** - 并非所有设备都支持语音识别，需检查 `isAvailable`
3. **网络要求** - 在线识别需要网络，离线识别更快但支持语言有限
4. **音频格式** - 传入的音频需匹配 `nativeAudioFormat` 格式
5. **后台识别** - 需要配置 `NSSupportsLiveSpeechRecognition` 支持后台识别
