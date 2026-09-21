# HappyBody · Health Lens for iOS

原生 SwiftUI + HealthKit App，面向一般成年人“日常健康与体能，兼顾有氧和力量”。iPhone / iOS 17+，无第三方依赖。此交付为可打开的开发工程，不是已签名安装包。

## 已实现

- HealthKit 只读授权：训练、睡眠、静息心率、HRV SDNN；读取最近 60 天。
- 今日建议：当天自评、训练计划、个人恢复趋势，输出维持计划、降低强度、优先恢复或数据不足。
- 周目标：用户确认强度后的有氧等效分钟、覆盖主要肌群的力量训练日数。
- 训练记录：运动后 Session-RPE 评分，`负荷 = 分钟 × 用力程度`。
- 每项健康指标独立选择来源；睡眠区间合并、训练重叠保守排除；缺失不补零。
- 历史散点图和每日值，模拟数据模式，与真实自评存储隔离。
- 隐私：无网络请求、无账号、无分析 SDK；HealthKit 数据只在内存中使用。用户自评与评分保存在本机受系统完整数据保护的文件，并排除备份。
- 页面内直接列出算法依据、阈值与局限。

## 在 iPhone 上运行

1. 在 Mac 安装完整 Xcode（建议 Xcode 16 或更新），并安装 iOS 平台支持。
2. 打开 `HealthLens.xcodeproj`，选择 **HealthLens** scheme。
3. Target → Signing & Capabilities：选择自己的开发 Team；若 bundle identifier 冲突，修改 `com.matrixchen.healthlens` 为自己的唯一标识。工程已包含 HealthKit capability 与只读用途说明。
4. 连接 iPhone，按系统提示信任电脑并开启开发者模式，选择该设备后 Run。
5. 首次进入确认适用范围；点“连接苹果健康”，在系统授权页自行选择允许的数据类型。
6. 完成“今日自评”，在“训练”页确认最近运动的强度与 RPE；在“依据”页核对数据来源。

开发签名需由你的 Apple 开发账号完成。能否使用 HealthKit entitlement 取决于所选 Team 的签名能力；若 Xcode 报 provisioning 错误，应按其具体提示配置。无需向聊天提供密码、私钥或证书。

模拟器可查看界面和示例；真实 HealthKit 授权、传感器数据与隐私设置必须在 iPhone 验证。

## 构建和测试

完整 Xcode 环境：

```sh
xcodebuild -project HealthLens.xcodeproj -scheme HealthLens \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
swift test
```

只有 Command Line Tools 时，运行同一组核心断言：

```sh
python3 scripts/test-core.py
```

`test-core.py` 仅将 XCTest 的断言接口适配为 Swift `precondition`，仍执行同一个测试文件中的测试方法；不会替换算法实现。不会访问健康数据。

当前环境实测和未完成项目见 `VALIDATION.md`。iOS SDK 不可用时，Swift 语法检查不能代替 iOS 类型检查与真机运行。

## 工程布局

- `App/`：SwiftUI 四页面、HealthKit 读取、本机受保护存储。
- `Sources/TrainingCore/`：无 HealthKit / UI 依赖的聚合与建议规则。
- `Tests/TrainingCoreTests/`：缺失数据、重复、时区、周统计、症状优先级等边界测试。
- `ALGORITHMS.md`：公式、证据层次和具体适用范围。
- `scripts/make_project.py`：重新生成 Xcode 工程与配置，不执行签名或联网。

当前 Xcode target 直接编译算法源文件；Swift Package 独立构建同一份源文件用于测试，没有两套实现。

## 首版有意保留的限制

- 不提供药物、康复或疾病相关运动处方；不预测受伤风险。
- HRV 使用 SDNN，统计检测是探索性辅助规则，没有把 RMSSD 论文阈值搬过来。
- 不使用 TRIMP、最大心率推断、ACWR 风险阈值、恢复百分比或自动加量。
- 力量训练不自动生成动作重量、组数或力竭目标；需要你的既有经验或教练计划。
- 跨来源互补运动暂不合并；“其他／间歇训练”可记录 RPE，但不自动计入有氧或力量目标。
- 只在前台读取或手动刷新，没有后台自动同步、通知、Apple Watch 独立 App 或云端模型。
- 尚未上传 App Store / TestFlight。当前没有签名 IPA。

## 1.1 更新（2026-09-17）

参考用户提供的 10.7 秒视频扩展真实数据功能：
- 今天页：睡眠、晨间 HRV、静息心率和步数快照，以及每周活动目标入口。
- 健康页：14 项指标卡片，支持 7 / 28 / 60 天趋势、每日读数、覆盖天数、来源和数据解释。
- 新增只读指标：步数、活动能量、爬楼、最大摄氧量、呼吸频率、血氧、睡眠手腕温度、体重、BMI、体脂率、去脂体重。
- 日志：每日自评历史、生活标签和备注；同一天更新而不重复，旧版记录自动兼容。
- 训练：近 28 天已评分 Session-RPE 负荷趋势。
- 计划和新手设置在真实模式下持久保存，示例修改不会覆盖真实设置。

升级后在健康页点击“更新健康读取权限”，自行选择允许读取的指标。无设备支持、未授权和没有记录均可能显示为空。新增指标用于观察，不直接改变已有恢复建议算法。无身体电量、实时压力、身体年龄等缺乏公开可验证依据的评分。
