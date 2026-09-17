# 验证记录

日期：2026-09-11。

## 已完成

- 使用 Apple Swift 6.1.2 在 macOS / arm64 编译并运行真实 TrainingCore 源码。
- `python3 scripts/test-core.py`：同一 XCTest 测试文件中的 **13 个测试方法通过**。只适配断言运行器，不替换算法。
- 测试内容：当日自评必需、过期自评失效、警示症状覆盖其他判断、身体不适/疲劳优先恢复、数据不足不判定恢复、持续异常须有当天与历史记录、单日 HRV 波动不作持续信号、原定休息不加练、睡眠区间去重、跨午夜/夏令时、未知强度与缺失 RPE、每周等效分钟和不同力量训练日、重叠/未来运动、重复采样不膨胀基线天数。
- `swiftc -frontend -parse`：全部 App 与核心 Swift 文件语法检查通过。
- `plutil -lint`：Xcode project.pbxproj、Info.plist、HealthKit entitlement、PrivacyInfo.xcprivacy 均通过。
- Xcode 工程文件引用与共享 scheme 的目标引用已检查。
- 图标为本地生成的几何图形，不含外部素材或健康数据。

## 环境限制，未完成

- `xcodebuild -version`：本机 active developer directory 只有 CommandLineTools，未找到完整 Xcode。
- `xcrun simctl` 不可用，因此没有模拟器构建或截图验证。
- `swift test` 已编译 TrainingCore，随后因缺少 XCTest 模块停止；使用独立运行器完成了上述同一组测试。
- **SwiftUI、Charts 与 HealthKit 的 iOS SDK 类型检查尚未完成**。语法检查与算法通过不能代替完整 iOS build。
- 未进行真机健康权限允许/拒绝/部分允许测试，未签名、安装、生成 IPA 或上传 TestFlight。
- 本组合建议规则没有前瞻性临床/运动干预验证；不宣称诊断或最优训练效果。

## Xcode 可用后的必要检查

1. 运行 README 中的 simulator build 命令，修复任何 SDK 或 UI 类型问题。
2. 模拟器验证四个页面、深浅色、较大字体、VoiceOver、示例退出及源切换。
3. iPhone 验证完整/部分/拒绝授权：空结果均不得表示已授权或身体正常。
4. 核对设备睡眠与 HRV 的来源、时间条件和聚合数值，与健康 App 对照。
5. 测试锁屏后本机记录读写保护、存储失败提示与清除；验证不会覆盖无法解码的原记录。
6. 验证示例不会覆盖真实自评与评分，退出后恢复本机记录。
7. 根据前瞻性用户反馈与运动专业评审改进建议规则，再考虑扩大适用范围。

## 2026-09-17 安装验证进展

- 已安装 Xcode 26.3（17C529），并选为当前开发工具。
- `swift test --scratch-path /private/tmp/HealthLensCoreTests`：原生 XCTest 13 项测试全部通过，0 失败。
- 使用 iPhoneOS 26.2 SDK、arm64-apple-ios17.0 target 对全部 App 与核心源码执行 `swiftc -typecheck`，通过且无诊断。
- 完整 `xcodebuild` 暂被缺少 iOS 平台组件阻断；已通过 Xcode Components 开始下载。类型检查不等于完整打包、签名或真机验证。
- 已识别已配对的 iPhone，安装仍需完成账户签名配置和手机开发者模式。尚未宣称安装成功。
