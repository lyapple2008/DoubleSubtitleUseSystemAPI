# SpeechRecognitionManager.swift 代码介绍

## 1. 导入的框架

```swift
import Foundation
import Speech
import AVFoundation
```

- **Foundation**: iOS 基础框架，提供基础数据类型和工具
- **Speech**: 系统语音识别框架 (SFSpeechRecognizer)
- **AVFoundation**: 音视频处理框架，用于处理音频数据

---

## 2. 协议 (Protocol)

```swift
protocol SpeechRecognitionDelegate: AnyObject {
    func speechRecognitionDidStart()
    func speechRecognitionDidStop()
    func speechRecognitionDidReceiveResult(_ result: String, isFinal: Bool)
    func speechRecognitionDidFail(with error: Error)
}
```

**解释**：
- `protocol` 是 Swift 的协议，类似于其他语言的"接口"
- `AnyObject` 表示这个协议只能被类实现（class-only protocol）
- 这是一个"委托模式" - 当语音识别发生各种事件时，通过 delegate 通知其他代码

---

## 3. 类定义 - 单例模式

```swift
final class SpeechRecognitionManager: NSObject {
    static let shared = SpeechRecognitionManager()
    ...
}
```

**关键点**：
- `final`: 防止被继承
- `NSObject`: 继承自 Foundation 的基类，获得面向对象能力
- `static let shared`: **单例模式** - 全局只有一个实例，保证语音识别服务统一管理

---

## 4. 私有属性

```swift
private var speechRecognizer: SFSpeechRecognizer?
private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
private var recognitionTask: SFSpeechRecognitionTask?

private var currentLocale: Locale = Locale(identifier: "en-US")
private var _isRecognizing = false
```

- 带有 `?` 表示**可选类型** (Optional)，可能为 nil
- `Locale` 表示语言区域设置
- `_isRecognizing` 使用下划线前缀是 Swift 的命名惯例，表示这是内部使用的属性

---

## 5. 计算属性 (Computed Property)

```swift
var isAvailable: Bool {
    speechRecognizer?.isAvailable ?? false
}
```

- 这不是存储属性，而是**计算属性** - 每次访问时动态计算
- `??` 是**空值合并运算符**，如果左边是 nil，返回右边的默认值

---

## 6. 核心方法

### 请求权限
```swift
func requestPermission(completion: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async {
            completion(status == .authorized)
        }
    }
}
```
- `@escaping` 表示闭包可以"逃逸" - 即便函数返回后闭包仍可被调用
- `DispatchQueue.main.async` 切换回主线程更新 UI

### 配置语言
```swift
func configure(locale: Locale) {
    currentLocale = locale
    speechRecognizer = SFSpeechRecognizer(locale: locale)
}
```

### 启动识别
```swift
func startRecognition() {
    // 1. 检查是否已在识别
    // 2. 创建识别请求
    // 3. 启动识别任务
    // 4. 回调处理结果
}
```

### 处理音频数据
```swift
func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    recognitionRequest.append(buffer)
}
```
- 接收外部传入的音频数据（来自 ReplayKit 捕获的系统音频）

---

## 7. 错误枚举

```swift
enum SpeechRecognitionError: LocalizedError {
    case notAvailable
    case permissionDenied
    case requestCreationFailed
}
```

- `enum` 是枚举类型
- `LocalizedError` 协议让错误可以本地化显示

---

## 8. 代码流程图

```
1. requestPermission()      → 请求语音识别权限
2. configure(locale:)       → 配置识别语言
3. startRecognition()       → 创建识别请求，启动识别任务
4. processAudioBuffer()    → 接收外部音频数据，传入识别引擎
5. delegate 回调           → 通知识别结果/错误/状态变化
6. stopRecognition()        → 停止识别
```

---

## 9. 关键技术点总结

| 概念 | 示例 |
|------|------|
| 单例 | `static let shared` |
| 可选类型 | `SFSpeechRecognizer?` |
| 闭包逃逸 | `@escaping` |
| 委托模式 | `delegate?` |
| 协议 | `protocol SpeechRecognitionDelegate` |
| 枚举 | `enum SpeechRecognitionError` |

这是 iOS 语音识别功能的核心管理类，负责与系统 `SFSpeechRecognizer` API 交互。
