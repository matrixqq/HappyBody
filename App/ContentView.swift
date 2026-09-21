import SwiftUI
import Charts
#if canImport(TrainingCore)
import TrainingCore
#endif

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group {
            if !model.adultAcknowledged { WelcomeView() }
            else {
                TabView {
                    NavigationStack { TodayView() }.tabItem { Label("今天", systemImage: "sun.max") }
                    NavigationStack { HealthDashboardView() }.tabItem { Label("健康", systemImage: "heart") }
                    NavigationStack { JournalView() }.tabItem { Label("日志", systemImage: "book.closed") }
                    NavigationStack { SessionsView() }.tabItem { Label("训练", systemImage: "figure.run") }
                    NavigationStack { MethodsView() }.tabItem { Label("依据", systemImage: "text.book.closed") }
                }
            }
        }
        .alert("提示", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("知道了", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var adult = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 52)).foregroundStyle(.blue).padding(.top, 34)
                    Text("HappyBody").font(.largeTitle.bold())
                    Text("让每次训练，\n都有恢复的空间。").font(.title2.weight(.medium))
                    Text("读取苹果健康里的运动、睡眠、心率、活动与身体指标，结合你的感受，提供日常训练与休息参考。")
                    Label("健康数据在本机计算，不上传", systemImage: "lock.shield")
                    Label("每条建议说明依据和数据局限", systemImage: "list.bullet.rectangle")
                    Label("不会写入或修改苹果健康记录", systemImage: "heart.text.square")
                    Text("适用于一般成年人日常健康与体能。疾病康复、孕期、伤病或专业竞赛训练需要个体化指导。本 App 不诊断疾病，也不能确认锻炼是否安全。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("我已满 18 岁，并了解上述适用范围", isOn: $adult)
                    Button("开始使用") { model.adultAcknowledged = adult }.buttonStyle(.borderedProminent).disabled(!adult)
                }.padding(26)
            }
        }
    }
}
struct DemoBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if model.demo {
            HStack { Label("示例模式 · 非你的健康结果", systemImage: "sparkles"); Spacer(); Button("退出") { model.leaveDemo() } }
                .font(.footnote).padding(12).background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @State private var showCheckIn = false
    private var color: Color {
        switch model.advice.level { case .medical: return .red; case .rest, .ease: return .orange; case .checkIn, .insufficient: return .secondary; case .maintain: return .blue }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DemoBanner()
                HealthSyncStatus()
                HStack {
                    VStack(alignment: .leading) {
                        Text(Date(), format: .dateTime.month().day().weekday()).foregroundStyle(.secondary)
                        Text("今天，怎么安排？").font(.title2.bold())
                    }
                    Spacer()
                    if model.busy { ProgressView() }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label(model.advice.title, systemImage: adviceIcon).font(.title3.bold()).foregroundStyle(color)
                    Text(model.advice.action).lineSpacing(4)
                    Divider()
                    ForEach(model.advice.evidence, id: \.self) { Text("• " + $0).font(.subheadline).foregroundStyle(.secondary) }
                    Text(model.advice.confidence).font(.caption).foregroundStyle(.secondary)
                }.padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                Button { showCheckIn = true } label: {
                    Label("记录今天的感受", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                VStack(alignment: .leading, spacing: 12) {
                    Text("原本打算做什么").font(.headline)
                    Picker("今天的计划", selection: $model.plan) {
                        Text("轻松活动").tag(Plan.easy); Text("有氧训练").tag(Plan.aerobic)
                        Text("力量训练").tag(Plan.strength); Text("休息").tag(Plan.rest)
                    }.pickerStyle(.menu)
                    Toggle("刚开始锻炼，或较久没有规律运动", isOn: $model.beginner).font(.subheadline)
                }
                TodayOverview()
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("苹果健康").font(.headline)
                    Text("读取最近 60 天；原始记录仅保留在内存中。没有记录可能是未授权或确实缺少数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(model.healthSheetCompleted ? "读取健康数据／检查授权" : "连接苹果健康") { Task { await model.connect() } }
                        .buttonStyle(.bordered).disabled(model.busy)
                    if model.snapshot.hasAnyData {
                        Text("数据更新时间 \(model.snapshot.loadedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.demo { Button("先看模拟示例") { model.showDemo() }.disabled(model.busy) }
                }
            }.padding(20)
        }.background(Color(.systemGroupedBackground)).navigationTitle("HappyBody")
            .sheet(isPresented: $showCheckIn) { CheckInView(initial: model.notes.checkIn) }
            .refreshable { await model.refresh() }
    }
    private var adviceIcon: String {
        switch model.advice.level { case .medical: return "exclamationmark.triangle"; case .rest: return "moon.zzz"; case .ease: return "leaf"; case .maintain: return "figure.walk"; default: return "questionmark.circle" }
    }
}
struct CheckInView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var fatigue: Int
    @State private var soreness: Int
    @State private var unwell = false
    @State private var warning = false
    @State private var tags: Set<String> = []
    @State private var note = ""
    private let options = ["晚睡", "规律作息", "工作繁忙", "饮酒", "睡前咖啡因", "旅行", "放松练习"]
    init(initial: CheckIn?) {
        let fresh = initial.flatMap { Calendar.current.isDateInToday($0.date) ? $0 : nil }
        _fatigue = State(initialValue: fresh?.fatigue ?? 2); _soreness = State(initialValue: fresh?.soreness ?? 1)
        _unwell = State(initialValue: fresh?.feelsUnwell ?? false); _warning = State(initialValue: fresh?.warningSymptoms ?? false)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("今天的感受") {
                    Stepper("疲劳程度：\(fatigue)/5", value: $fatigue, in: 1...5)
                    Text("1 精力充足 · 3 一般疲劳 · 5 非常疲劳").font(.caption).foregroundStyle(.secondary)
                    Stepper("肌肉酸痛：\(soreness)/5", value: $soreness, in: 1...5)
                    Text("1 无明显酸痛 · 3 中等 · 5 明显影响动作").font(.caption).foregroundStyle(.secondary)
                }
                Section("生活标签") {
                    ForEach(options, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(get: { tags.contains(tag) }, set: { selected in if selected { tags.insert(tag) } else { tags.remove(tag) } }))
                    }
                    TextField("补充记录（可选）", text: $note, axis: .vertical).lineLimit(3...6)
                    Text("标签只用于回顾，不据此推断因果或改变训练建议。").font(.caption).foregroundStyle(.secondary)
                }
                Section("优先关注身体感受") {
                    Toggle("今天身体不适或发热", isOn: $unwell)
                    Toggle("有胸痛、晕厥或异常气短", isOn: $warning)
                    if warning { Text("若症状正在发生、严重或持续，请立即联系当地急救服务，不要等待 App 的建议。").foregroundStyle(.red) }
                }
                Section { Text("自评每天重新确认。真实模式下仅保存于本机受系统数据保护的文件中，不上传，也不写回苹果健康。").font(.footnote) }
            }.navigationTitle("今日自评").onAppear {
                if let entry = model.notes.entries.first(where: { Calendar.current.isDateInToday($0.checkIn.date) }) { tags = Set(entry.tags); note = entry.note }
            }.toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if model.checkIn(CheckIn(fatigue: fatigue, soreness: soreness, feelsUnwell: unwell, warningSymptoms: warning), tags: tags.sorted(), note: String(note.prefix(2000))) { dismiss() } } }
            }
        }
    }
}
struct WeekView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DemoBanner()
                Text("最近 7 天，含今天").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Text("有氧活动").font(.headline)
                    Text("\(Int(model.week.equivalentMinutes)) / 150 分钟").font(.largeTitle.weight(.semibold)).foregroundStyle(.blue)
                    ProgressView(value: min(model.week.equivalentMinutes / 150, 1))
                    Text("中等强度等效分钟＝已确认中等强度分钟＋2 × 高强度分钟。150 是一般成人参考起点，不要求新手立即达到。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.week.unknownAerobicSessions > 0 { Text("另有 \(model.week.unknownAerobicSessions) 次有氧记录未确认强度，尚未计入。").font(.subheadline) }
                    Text("未佩戴、未记录或来自其他来源的运动不会自动计入；缺少记录不代表没有运动。").font(.caption).foregroundStyle(.secondary)
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    Text("力量训练").font(.headline)
                    Text("\(model.week.strengthDays) / 2 天").font(.largeTitle.weight(.semibold))
                    Text("仅计入你确认覆盖主要肌群、且达到中等或更高强度的训练日。同一天多次训练计作一天。不能仅凭运动类型证明满足指南要求。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.card()
                VStack(alignment: .leading, spacing: 12) {
                    Text("已评分训练负荷").font(.headline)
                    Text("\(Int(model.week.recordedLoad)) AU").font(.title.bold())
                    Text("\(model.week.ratedSessions)/\(model.week.totalSessions) 次训练有用力评分。负荷＝分钟 × Session-RPE（0–10）。未评分不按零值处理，不能与记录完整的一周直接比较。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.card()
                LoadHistoryCard()
                TrendCard(title: "晨间 HRV · SDNN", unit: "ms", points: model.snapshot.hrv)
                TrendCard(title: "静息心率", unit: "次/分", points: model.snapshot.restingHR)
                TrendCard(title: "睡眠时长", unit: "小时", points: model.snapshot.sleep)
            }.padding(20)
        }.background(Color(.systemGroupedBackground)).navigationTitle("每周观察").refreshable { await model.refresh() }
    }
}
private struct TrendCard: View {
    let title: String
    let unit: String
    let points: [DayValue]
    private var visible: [DayValue] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Calendar.current.startOfDay(for: Date()))!
        return points.filter { $0.date >= cutoff && $0.date <= Date() }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if visible.isEmpty { Text("没有可用记录").foregroundStyle(.secondary) }
            else {
                Chart(visible) { p in
                    PointMark(x: .value("日期", p.date), y: .value(unit, p.value)).foregroundStyle(.blue)
                }.frame(height: 150).accessibilityLabel(title + "，最近记录日趋势")
                Text("\(visible.count) 个记录日 · 缺失日期不补零 · 单位 \(unit)").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("每日数值") {
                    ForEach(visible.reversed()) { p in
                        HStack { Text(p.date, format: .dateTime.month().day()); Spacer(); Text(p.value, format: .number.precision(.fractionLength(1))); Text(unit) }.font(.subheadline)
                    }
                }
            }
        }.card()
    }
}
struct SessionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: Session?
    var body: some View {
        List {
            if model.demo { Section { DemoBanner() } }
            Section {
                NavigationLink { WeekView() } label: { Label("每周目标与负荷趋势", systemImage: "chart.bar.xaxis") }
                LabeledContent("近 7 天已评分", value: "\(model.week.ratedSessions) / \(model.week.totalSessions) 次")
            }
            Section {
                Text("运动结束后约 30 分钟，回顾整次训练的用力程度。这里的评分独立于苹果自动估算，未填写不会生成负荷。").font(.footnote)
            }
            if model.snapshot.sessions.isEmpty { ContentUnavailableView("还没有训练记录", systemImage: "figure.walk", description: Text("先在“今天”连接苹果健康；也可能未允许读取或所选来源没有记录。")) }
            ForEach(model.snapshot.sessions.sorted { $0.start > $1.start }) { session in
                Button { selected = session } label: {
                    HStack {
                        Image(systemName: session.kind == .strength ? "dumbbell" : "figure.walk").frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.title).font(.headline)
                            Text(session.start, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            Text("\(Int(session.minutes)) 分钟 · \(session.source)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let rpe = model.notes.ratings[session.id]?.rpe { Text("RPE \(rpe)").font(.subheadline) } else { Text("待评分").font(.subheadline) }
                    }
                }.foregroundStyle(.primary)
            }
            Section {
                Text("为避免重复，训练只采用所选来源；可在“依据”页切换。重叠训练保守保留先开始的记录，同时开始优先保留较长记录；本次忽略 \(model.snapshot.omittedWorkouts) 条。跨来源互补记录暂不合并。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("训练记录").sheet(item: $selected) { RatingView(session: $0, existing: model.notes.ratings[$0.id]) }
    }
}
struct RatingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let session: Session
    @State var rated: Bool
    @State var rpe: Int
    @State var intensity: Intensity
    @State var muscle: Bool
    init(session: Session, existing: SessionRating?) {
        self.session = session; _rated = State(initialValue: existing?.rpe != nil); _rpe = State(initialValue: existing?.rpe ?? 3)
        _intensity = State(initialValue: existing?.intensity ?? .unknown); _muscle = State(initialValue: existing?.majorMuscleGroups ?? false)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("整次训练的感觉") {
                    Toggle("我已回顾并确认评分", isOn: $rated)
                    Stepper("主观用力程度：\(rpe)/10", value: $rpe, in: 0...10).disabled(!rated)
                    Text("0 无用力 · 2 轻松 · 3 中等 · 5 较吃力 · 7 很吃力 · 10 最大用力。请对整次训练评分，而不是最高强度的片段。").font(.footnote)
                    if rated { Text("Session-RPE 负荷：\(Int(session.minutes * Double(rpe))) AU") }
                }
                Section("用于每周活动统计") {
                    Picker("实际活动强度", selection: $intensity) {
                        Text("不确定").tag(Intensity.unknown); Text("轻松").tag(Intensity.light)
                        Text("中等").tag(Intensity.moderate); Text("高强度").tag(Intensity.vigorous)
                    }
                    Text("有氧活动可参考谈话测试：中等强度能交谈但不能唱歌；高强度通常说几个词就需停下来换气。不要仅凭 RPE 数字自动分类。").font(.footnote)
                    if session.kind == .strength { Toggle("本次覆盖主要肌群", isOn: $muscle) }
                    if session.kind == .other { Text("此类型暂不自动计入有氧或力量周目标，仍可记录训练负荷。").font(.footnote) }
                }
            }.navigationTitle(session.title).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if model.rate(session, rating: SessionRating(rpe: rated ? rpe : nil, intensity: intensity, majorMuscleGroups: muscle)) { dismiss() } } }
            }
        }
    }
}
struct MethodsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmClear = false
    private let keys = HealthMetric.allCases.filter { !$0.cumulative }.map { ($0.rawValue, $0.title) } + [("workouts", "训练")]
    var body: some View {
        List {
            Section("建议如何产生 · v" + TrainingEngine.version) {
                Text("① 今日不适与自评优先\n② WHO 周目标与 Session-RPE 记录训练\n③ HRV、静息心率和睡眠辅助保守调整\n④ 数据不足时降低结论强度，不生成恢复分数")
                Text("疲劳／酸痛 ≥4/5 优先恢复；多项信息一致时建议降低强度。阈值与组合规则是本产品的保守启发式，尚未经前瞻性验证，不等于论文中验证过的完整训练方案。").font(.footnote)
            }
            Section("数据来源") {
                ForEach(keys, id: \.0) { key, title in
                    if let options = model.snapshot.sources[key], !options.isEmpty {
                        Picker(title, selection: Binding(get: { model.snapshot.selected[key] ?? options[0].id }, set: { id in Task { await model.chooseSource(key: key, id: id) } })) {
                            ForEach(options) { source in Text(source.name).tag(source.id) }
                        }.disabled(model.busy || model.demo)
                    } else { LabeledContent(title, value: "无可用来源") }
                }
                Text("默认优先选择近 14 天覆盖日期最多的来源。每项指标只选一个来源；不同设备可能没有互补合并。使用当前时区解释日期，跨时区旅行时需谨慎比较。").font(.footnote)
            }
            Section("HRV 和睡眠的限制") {
                Text("仅读取同一来源 05:00–11:00 的 SDNN，取每日中位数；时间一致不代表姿势、呼吸和测量条件一致。不会从 SDNN 推算 RMSSD，也不套用 RMSSD 论文阈值。")
                Text("基线为今日前第 35 至第 8 天（28 个日历日），至少 14 个记录日。对 ln(SDNN) 及静息心率使用中位数 ± 2×1.4826×MAD；最近 3 日至少 2 日、且包含今日超界才提示持续偏离。MAD 为零时不作异常判断。此统计范围不是医学正常范围。")
                Text("睡眠只合并同一来源的入睡区间，排除卧床与清醒。中午到次日中午为一个窗口，归于结束日；最新窗口可能尚未完整。少于 7 小时仅是一般成人参考提示，漏戴会低估。")
            }.font(.footnote)
            Section("原始资料") {
                Link("WHO：身体活动指南", destination: URL(string: "https://www.who.int/publications/i/item/9789240015128")!)
                Link("Foster 2001：Session-RPE", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/11708692/")!)
                Link("Vesterinen 2016：HRV 引导耐力训练", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/26909534/")!)
                Link("HRV 引导训练：系统综述", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC8507742/")!)
                Link("CDC：判断运动强度", destination: URL(string: "https://www.cdc.gov/physical-activity-basics/measuring/index.html")!)
                Link("CDC：睡眠建议", destination: URL(string: "https://www.cdc.gov/sleep/about/index.html")!)
                Link("Apple：健康数据授权机制", destination: URL(string: "https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data")!)
            }
            Section("隐私与本机记录") {
                Text("不注册账号、不调用云端模型、不含广告或分析 SDK。HealthKit 原始数据仅在内存处理；自评历史、生活标签、备注与评分保存在本机受系统数据保护的文件中，并排除备份。外部资料链接由浏览器打开。")
                Text("清除本机日志与评分不会修改苹果健康记录。撤销健康读取权限，请前往「健康」App 的应用权限设置。")
                Button("清除本机日志与评分", role: .destructive) { confirmClear = true }
            }.font(.footnote)
        }.navigationTitle("算法与依据").confirmationDialog("清除日志、自评和训练评分？此操作无法撤销，不影响苹果健康。", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除本机记录", role: .destructive) { model.clearNotes() }
        }
    }
}
private extension View {
    func card() -> some View { self.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)) }
}


private struct MetricTile: View {
    @EnvironmentObject var model: AppModel
    let metric: HealthMetric
    private var latest: DayValue? { model.snapshot.points(metric).last }
    var body: some View {
        NavigationLink { MetricDetailView(metric: metric) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: metric.icon).foregroundStyle(.teal); Text(metric.title).font(.subheadline); Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                if let latest {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(latest.value, format: .number.precision(.fractionLength(metric.cumulative ? 0 : 1))).font(.title2.bold())
                        Text(metric.unitLabel).font(.caption).foregroundStyle(.secondary)
                    }.minimumScaleFactor(0.7).lineLimit(1)
                    Text(Calendar.current.isDateInToday(latest.date) ? (metric.cumulative ? "今天 · 持续累计" : "今日记录") : "最近记录 · " + latest.date.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.title2.bold())
                    Text("无记录或未授权").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
struct HealthDashboardView: View {
    @EnvironmentObject var model: AppModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DemoBanner()
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("了解身体的变化").font(.title2.bold())
                        Text("最近 60 天 · 点开指标查看趋势与来源").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.busy { ProgressView() }
                }
                HealthSyncStatus()
                group("恢复与身体指标", metrics: [.sleep, .hrv, .hr, .respiration, .oxygen, .wrist, .vo2])
                group("日常活动", metrics: [.steps, .energy, .floors])
                group("身体成分", metrics: [.weight, .bmi, .fat, .lean])
                VStack(alignment: .leading, spacing: 10) {
                    Text("新增指标需要读取授权").font(.headline)
                    Text("升级后请点下方按钮选择允许读取的项目。不支持的设备、没有历史记录或未授权都会显示为空；不会用零或示例替代。").font(.footnote).foregroundStyle(.secondary)
                    Button("更新健康读取权限") { Task { await model.connect() } }.buttonStyle(.bordered).disabled(model.busy)
                    ForEach(model.snapshot.readWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }.card()
            }.padding(20)
        }.background(Color(.systemGroupedBackground)).navigationTitle("健康看板").refreshable { await model.refresh() }
    }
    private func group(_ title: String, metrics: [HealthMetric]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, spacing: 12) { ForEach(metrics) { MetricTile(metric: $0) } }
        }
    }
}
private struct MetricDetailView: View {
    @EnvironmentObject var model: AppModel
    let metric: HealthMetric
    @State private var days = 28
    private var points: [DayValue] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: model.now))!
        return model.snapshot.points(metric).filter { $0.date >= cutoff && $0.date <= model.now }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DemoBanner()
                Picker("时间范围", selection: $days) { Text("7 天").tag(7); Text("28 天").tag(28); Text("60 天").tag(60) }.pickerStyle(.segmented)
                if let latest = points.last {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(latest.value, format: .number.precision(.fractionLength(metric.cumulative ? 0 : 1))).font(.system(size: 42, weight: .semibold)) + Text(" " + metric.unitLabel).font(.subheadline)
                        Text("最近记录日：" + latest.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Chart(points) { p in
                        if metric.cumulative { BarMark(x: .value("日期", p.date, unit: .day), y: .value(metric.unitLabel, p.value)).foregroundStyle(.teal.gradient) }
                        else { PointMark(x: .value("日期", p.date), y: .value(metric.unitLabel, p.value)).foregroundStyle(.teal) }
                    }.frame(height: 210).accessibilityLabel(metric.title + "记录日趋势")
                    HStack {
                        VStack(alignment: .leading) { Text("有记录").font(.caption).foregroundStyle(.secondary); Text("\(points.count) / \(days) 天").font(.headline) }
                        Spacer()
                        VStack(alignment: .trailing) { Text("记录日中位数").font(.caption).foregroundStyle(.secondary); Text(Aggregation.median(points.map(\.value)) ?? 0, format: .number.precision(.fractionLength(1))).font(.headline) }
                    }.card()
                    DisclosureGroup("每日记录") {
                        ForEach(points.reversed()) { point in
                            HStack { Text(point.date, format: .dateTime.month().day()); Spacer(); Text(point.value, format: .number.precision(.fractionLength(metric.cumulative ? 0 : 1))); Text(metric.unitLabel) }.font(.subheadline).padding(.vertical, 5)
                        }
                    }
                } else { ContentUnavailableView("该时间段没有记录", systemImage: metric.icon, description: Text("可切换到 60 天，或在健康看板更新读取权限。缺失不代表身体异常。")) }
                VStack(alignment: .leading, spacing: 12) {
                    Label("数据解释", systemImage: "info.circle").font(.headline)
                    Text(metric.note)
                    Text("缺失日期不补零；较早的读数不会被标记为今日状态。统计范围不是医学正常范围。")
                    Text("来源：" + (model.demo ? "模拟数据" : model.snapshot.sourceName(metric)))
                    if !metric.cumulative, let options = model.snapshot.sources[metric.rawValue], !options.isEmpty {
                        Picker("切换来源", selection: Binding(get: { model.snapshot.selected[metric.rawValue] ?? options[0].id }, set: { id in Task { await model.chooseSource(key: metric.rawValue, id: id) } })) {
                            ForEach(options) { Text($0.name).tag($0.id) }
                        }.disabled(model.demo || model.busy)
                    }
                }.font(.footnote).foregroundStyle(.secondary).card()
            }.padding(20)
        }.background(Color(.systemGroupedBackground)).navigationTitle(metric.title)
    }
}
private struct TodayOverview: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("身体快照").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach([HealthMetric.sleep, .hrv, .hr, .steps]) { MetricTile(metric: $0) }
            }
            NavigationLink { WeekView() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本周训练与恢复").font(.headline)
                        Text("有氧 \(Int(model.week.equivalentMinutes))/150 分钟 · 力量 \(model.week.strengthDays)/2 天").font(.caption)
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }.card()
            }.buttonStyle(.plain)
        }
    }
}
struct JournalView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing = false
    var body: some View {
        List {
            if model.demo { Section { DemoBanner() } }
            Section {
                Button { editing = true } label: { Label("记录／更新今日感受", systemImage: "square.and.pencil") }
                Text("每天一条，重复保存更新当天记录；历史记录保留在本机。标签与感受用于个人回顾，不证明因果关系。").font(.footnote).foregroundStyle(.secondary)
            }
            if model.notes.entries.isEmpty { ContentUnavailableView("从今天开始记录", systemImage: "book.closed", description: Text("记录疲劳、酸痛与生活习惯，让恢复建议有你的感受作为依据。")) }
            ForEach(model.notes.entries) { entry in
                Section(entry.checkIn.date.formatted(.dateTime.year().month().day().weekday())) {
                    HStack {
                        Label("疲劳 \(entry.checkIn.fatigue)/5", systemImage: "battery.50percent")
                        Spacer()
                        Label("酸痛 \(entry.checkIn.soreness)/5", systemImage: "figure.flexibility")
                    }.font(.subheadline)
                    if entry.checkIn.feelsUnwell { Label("记录了身体不适", systemImage: "cross.case").foregroundStyle(.orange) }
                    if entry.checkIn.warningSymptoms { Label("记录了警示症状", systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                    if !entry.tags.isEmpty { Text(entry.tags.joined(separator: " · ")).font(.subheadline).foregroundStyle(.teal) }
                    if !entry.note.isEmpty { Text(entry.note).font(.subheadline) }
                }
            }
        }.navigationTitle("生活日志").sheet(isPresented: $editing) { CheckInView(initial: model.notes.checkIn) }
    }
}
private struct LoadHistoryCard: View {
    @EnvironmentObject var model: AppModel
    private var rated: [Session] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -27, to: Calendar.current.startOfDay(for: model.now))!
        return model.snapshot.sessions.filter { $0.start >= cutoff && $0.end <= model.now && model.notes.ratings[$0.id]?.load(minutes: $0.minutes) != nil }.sorted { $0.start < $1.start }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近 28 天训练负荷").font(.headline)
            if rated.isEmpty { Text("为训练添加 RPE 评分后显示趋势。").foregroundStyle(.secondary) }
            else {
                Chart(rated) { session in
                    BarMark(x: .value("日期", session.start, unit: .day), y: .value("AU", model.notes.ratings[session.id]?.load(minutes: session.minutes) ?? 0)).foregroundStyle(.indigo.gradient)
                }.frame(height: 170)
            }
            Text("仅绘制已评分训练。空白日可能是休息、漏记或未评分；不据此计算身体电量、实时压力或受伤风险。").font(.caption).foregroundStyle(.secondary)
        }.card()
    }
}


private struct HealthSyncStatus: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if !model.demo {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: model.busy ? "arrow.triangle.2.circlepath" : "heart.text.square").foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.syncStatus).font(.subheadline.weight(.medium))
                        if model.snapshot.completedQueries > 0 {
                            Text(model.snapshot.loadedAt, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("刷新") { Task { if model.healthSheetCompleted { await model.refresh() } else { await model.connect() } } }.disabled(model.busy)
                }
                if model.busy { ProgressView(value: Double(model.snapshot.completedQueries), total: Double(HealthSnapshot.queryCount)) }
                if model.snapshot.completedQueries > 0 {
                    DisclosureGroup("查看读取结果") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(HealthMetric.allCases) { metric in
                                HStack {
                                    Text(metric.title)
                                    Spacer()
                                    Text(model.snapshot.readCounts[metric.rawValue] == nil ? (model.busy ? "等待返回" : "读取失败") : "\(model.snapshot.points(metric).count) 个记录日")
                                }
                            }
                            Text("晨间 HRV（用于建议）：\(model.snapshot.hrv.count) 个记录日")
                            Text("训练：\(model.snapshot.sessions.count) 次")
                            ForEach(model.snapshot.readWarnings.sorted(), id: \.self) { Text($0).foregroundStyle(.orange) }
                            Text("0 条表示健康系统没有返回记录，可能是没有数据或未允许读取，App 无法区分。请在健康 App → 头像 → App → HappyBody 检查读取权限。")
                            Text("HRV 看板显示全天记录；建议只用晨间记录，因而可能显示不同的覆盖天数。")
                            Button("检查健康读取权限") { Task { await model.connect() } }.disabled(model.busy)
                        }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }.font(.footnote)
                }
            }.card()
        }
    }
}
