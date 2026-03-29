# TranslationManager.swift 代码详解

这是一份面向 Swift/iOS 开发小白的完整指南。

---

## 一、Swift 语法基础

### 1. `#if canImport(...)` - 条件编译

```swift
#if canImport(Translation)
import Translation
#endif
```

- `canImport` 是一个编译检查指令
- 如果系统支持 `Translation` 框架，就导入它
- 用于兼容不同 iOS 版本

**类似语法：**
```swift
#if canImport(UIKit)
import UIKit
#endif
```

### 2. `protocol` - 协议（类似接口）

```swift
protocol TranslationDelegate: AnyObject {
    func translationDidComplete(originalText: String, translatedText: String)
    func translationDidFail(with error: Error)
}
```

- 协议定义了一组方法签名
- 类通过 `:` 采用协议并实现方法
- 类似于 Java 的 Interface

```swift
// 采用协议
class MyClass: TranslationDelegate {
    func translationDidComplete(originalText: String, translatedText: String) {
        // 实现翻译完成逻辑
    }

    func translationDidFail(with error: Error) {
        // 处理错误
    }
}
```

### 3. `weak var` - 弱引用

```swift
weak var delegate: TranslationDelegate?
```

- 防止循环引用（内存泄漏）
- 修饰可空（Optional）的引用类型
- 对象销毁后自动变为 `nil`

### 4. `defer` - 延迟执行

```swift
func translate(_ text: String) async throws -> String {
    isTranslating = true
    defer { isTranslating = false }  // 函数结束时执行

    // ... 翻译逻辑
}
```

- `defer` 块中的代码**一定会执行**
- 无论函数是正常返回还是抛出异常
- 常用于清理资源

### 5. `async/await` - 异步编程

```swift
func translate(_ text: String) async throws -> String {
    // async - 异步函数，可以暂停执行
    // throws - 可能抛出错误
}
```

- `async` - 异步函数，不会阻塞主线程
- `await` - 等待异步操作完成
- `throws` - 可能抛出错误，需要处理

```swift
// 调用异步函数
Task {
    do {
        let result = try await translationManager.translate("你好")
        print(result)
    } catch {
        print("翻译失败: \(error)")
    }
}
```

### 6. `#available` - 版本检查

```swift
if #available(iOS 26.0, *) {
    return try await translateWithSystemAPI(text)
} else {
    return try await translateWithPlaceholder(text)
}
```

- 检查代码是否在特定 iOS 版本运行
- 如果是 iOS 26.0+，使用系统翻译 API
- 否则使用占位符实现

### 7. `enum` - 枚举

```swift
enum TranslationError: LocalizedError {
    case notAvailable
    case translationFailed
    case languageNotSupported
}
```

- 定义一组相关的常量
- `LocalizedError` 协议：提供本地化错误描述
- 类似于其他语言的 Enum

```swift
// 使用枚举
throw TranslationError.notAvailable

// 匹配枚举值
switch error {
case .notAvailable:
    print("翻译不可用")
case .translationFailed:
    print("翻译失败")
case .languageNotSupported:
    print("语言不支持")
}
```

### 8. `Locale.Language` - 语言标识

```swift
let sourceLanguageCode = Locale.Language(identifier: sourceLanguage.code)
let targetLanguageCode = Locale.Language(identifier: targetLanguage.code)
```

- iOS 用来表示语言的对象
- `Locale.Language` 是 iOS 15+ 引入的新 API
- 可以表示复杂语言标签（如 "zh-Hans-CN"）

---

## 二、iOS 系统翻译功能

### 1. 什么是 Translation 框架？

iOS 系统自带的翻译框架（`Translation`）从 iOS 17 开始引入，提供：
- 离线翻译支持
- 多语言翻译
- 系统级集成

### 2. 使用条件

```swift
// iOS 26.0+ 使用新 API
if #available(iOS 26.0, *) {
    // 使用 TranslationSession
}

// iOS 17-25 使用旧 API 或占位符
else {
    // 降级处理
}
```

### 3. 翻译会话创建流程

```
┌─────────────────────────────────────────────────────────────┐
│                 翻译 API 使用流程                            │
├─────────────────────────────────────────────────────────────┤
│ 1. 指定源语言和目标语言                                      │
│    Locale.Language(identifier: "zh")                       │
│    Locale.Language(identifier: "en")                       │
│                                                             │
│ 2. 创建翻译会话                                              │
│    TranslationSession(                                     │
│        installedSource: sourceLanguage,                    │
│        target: targetLanguage                              │
│    )                                                       │
│                                                             │
│ 3. 执行翻译                                                  │
│    session.translate(text)                                 │
│                                                             │
│ 4. 获取结果                                                 │
│    response.targetText                                     │
└─────────────────────────────────────────────────────────────┘
```

### 4. 代码示例

```swift
// iOS 26.0+ 的翻译实现
@available(iOS 26.0, *)
private func translateWithSystemAPI(_ text: String) async throws -> String {
    // 1. 创建语言对象
    let sourceLanguageCode = Locale.Language(identifier: sourceLanguage.code)
    let targetLanguageCode = Locale.Language(identifier: targetLanguage.code)

    // 2. 创建翻译会话
    let session = TranslationSession(
        installedSource: sourceLanguageCode,
        target: targetLanguageCode
    )

    // 3. 执行翻译
    let response = try await session.translate(text)

    // 4. 返回翻译结果
    return response.targetText
}
```

### 5. 版本兼容策略

```swift
func translate(_ text: String) async throws -> String {
    // 编译时检查 iOS 版本
    if #available(iOS 26.0, *) {
        // iOS 26.0+ 使用完整功能
        return try await translateWithSystemAPI(text)
    } else {
        // 旧版本使用降级方案
        return try await translateWithPlaceholder(text)
    }
}
```

| iOS 版本 | 翻译方案 |
|---------|---------|
| iOS 26.0+ | 系统 Translation 框架（完整功能） |
| iOS 17-25 | 降级处理（占位符或第三方 API） |
| iOS 16- | 降级处理 |

### 6. 错误处理

```swift
enum TranslationError: LocalizedError {
    case notAvailable        // 翻译服务不可用
    case translationFailed   // 翻译过程失败
    case languageNotSupported // 语言不支持

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Translation is not available on this device"
        case .translationFailed:
            return "Translation failed"
        case .languageNotSupported:
            return "The selected language pair is not supported"
        }
    }
}
```

### 7. 异步调用模式

```swift
// 在 ContentViewModel 中调用翻译
Task { [weak self] in
    guard let self = self else { return }
    do {
        let translatedText = try await TranslationManager.shared.translate(text)
        await MainActor.run {
            self.updateTranslatedSubtitle(subtitleID: job.subtitleID, translatedText: translatedText)
        }
    } catch {
        await MainActor.run {
            self.updateTranslatedSubtitle(subtitleID: job.subtitleID, translatedText: "翻译失败")
        }
    }
}
```

---

## 三、总结

### Swift 语法要点

| 语法 | 说明 |
|------|------|
| `#if canImport(...)` | 条件编译，检查模块是否可用 |
| `protocol` | 协议，类似 Java 接口 |
| `weak var` | 弱引用，防止循环引用 |
| `defer` | 延迟执行，无论如何都运行 |
| `async/await` | 异步编程 |
| `#available` | iOS 版本检查 |
| `enum` | 枚举 |
| `Locale.Language` | 语言标识对象 |

### iOS 翻译功能要点

| 要点 | 说明 |
|------|------|
| Translation 框架 | iOS 17+ 系统翻译框架 |
| TranslationSession | iOS 26+ 新 API |
| 版本兼容 | 使用 #available 做降级处理 |
| 错误处理 | 实现 LocalizedError 协议 |
