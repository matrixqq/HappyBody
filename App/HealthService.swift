import Foundation
import HealthKit
#if canImport(TrainingCore)
import TrainingCore
#endif

struct HealthSource: Identifiable, Hashable {
    let id: String
    let name: String
}
enum HealthMetric: String, CaseIterable, Identifiable {
    case hrv, hr, sleep, steps, energy, floors, vo2, respiration, oxygen, wrist, weight, bmi, fat, lean
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hrv: return "HRV · SDNN"; case .hr: return "静息心率"; case .sleep: return "睡眠时长"
        case .steps: return "步数"; case .energy: return "活动能量"; case .floors: return "爬楼层数"
        case .vo2: return "最大摄氧量"; case .respiration: return "呼吸频率"; case .oxygen: return "血氧饱和度"
        case .wrist: return "睡眠手腕温度"; case .weight: return "体重"; case .bmi: return "BMI"
        case .fat: return "体脂率"; case .lean: return "去脂体重"
        }
    }
    var unitLabel: String {
        switch self {
        case .hrv: return "ms"; case .hr: return "次/分"; case .sleep: return "小时"
        case .steps: return "步"; case .energy: return "千卡"; case .floors: return "层"
        case .vo2: return "mL/kg/min"; case .respiration: return "次/分"; case .oxygen, .fat: return "%"
        case .wrist: return "°C"; case .weight, .lean: return "kg"; case .bmi: return "kg/m²"
        }
    }
    var icon: String {
        switch self {
        case .hrv: return "waveform.path.ecg"; case .hr: return "heart.fill"; case .sleep: return "moon.zzz.fill"
        case .steps: return "figure.walk"; case .energy: return "flame.fill"; case .floors: return "figure.stairs"
        case .vo2, .respiration: return "lungs.fill"; case .oxygen: return "drop.fill"; case .wrist: return "thermometer.medium"
        default: return "scalemass.fill"
        }
    }
    var cumulative: Bool { [.steps, .energy, .floors].contains(self) }
    var identifier: HKQuantityTypeIdentifier? {
        switch self {
        case .hrv: return .heartRateVariabilitySDNN; case .hr: return .restingHeartRate; case .sleep: return nil
        case .steps: return .stepCount; case .energy: return .activeEnergyBurned; case .floors: return .flightsClimbed
        case .vo2: return .vo2Max; case .respiration: return .respiratoryRate; case .oxygen: return .oxygenSaturation
        case .wrist: return .appleSleepingWristTemperature; case .weight: return .bodyMass; case .bmi: return .bodyMassIndex
        case .fat: return .bodyFatPercentage; case .lean: return .leanBodyMass
        }
    }
    var unit: HKUnit {
        switch self {
        case .hrv: return .secondUnit(with: .milli); case .hr, .respiration: return .count().unitDivided(by: .minute())
        case .sleep: return .hour(); case .energy: return .kilocalorie(); case .vo2: return .literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case .oxygen, .fat: return .percent(); case .wrist: return .degreeCelsius(); case .weight, .lean: return .gramUnit(with: .kilo)
        default: return .count()
        }
    }
    var multiplier: Double { [.oxygen, .fat].contains(self) ? 100 : 1 }
    var note: String {
        switch self {
        case .hrv: return "看板显示同一来源全天 SDNN 的每日中位数；建议仍只使用 05:00–11:00 的非手动晨间记录。中位数与健康 App 的平均值可能不同。"
        case .sleep: return "同一来源的入睡区间去重，按中午至次日中午归属；不是睡眠质量评分。"
        case .wrist: return "Apple Watch 睡眠手腕温度读数，不等于核心体温，不能用于判断发热。"
        case .vo2: return "读取健康 App 保存的最大摄氧量估计。记录可能不频繁；不据此推算身体年龄。"
        case .oxygen: return "可穿戴设备血氧读数受佩戴、运动等影响；本 App 不使用它判断训练安全。"
        case .energy: return "仅活动能量，不含静息消耗；没有完整饮食记录时不能推算热量缺口。"
        case .bmi: return "直接读取健康 App 中的 BMI 记录，不用不同日期的身高体重重新估算。"
        default: return cumulative ? "使用 HealthKit 每日累计统计，避免直接相加手机和手表的重叠样本。当天数值尚未完整。" : "同一来源的每日中位数，仅描述个人记录趋势；不以通用阈值标记优劣。"
        }
    }
}
struct HealthSnapshot {
    var hrv: [DayValue] = []
    var restingHR: [DayValue] = []
    var sleep: [DayValue] = []
    var sessions: [Session] = []
    var sources: [String: [HealthSource]] = [:]
    var selected: [String: String] = [:]
    var metrics: [String: [DayValue]] = [:]
    var readWarnings: [String] = []
    var completedQueries = 0
    var readCounts: [String: Int] = [:]
    static let queryCount = HealthMetric.allCases.count + 1
    var availableMetricCount: Int { HealthMetric.allCases.filter { !points($0).isEmpty }.count }
    var summary: String { "\(availableMetricCount)/\(HealthMetric.allCases.count) 项指标有记录 · \(sessions.count) 次训练" }
    func points(_ metric: HealthMetric) -> [DayValue] {
        switch metric { case .hrv: return metrics["hrv"] ?? hrv; case .hr: return restingHR; case .sleep: return sleep; default: return metrics[metric.rawValue] ?? [] }
    }
    func sourceName(_ metric: HealthMetric) -> String {
        if metric.cumulative { return "Apple Health 日累计统计" }
        return sources[metric.rawValue]?.first { $0.id == selected[metric.rawValue] }?.name ?? "无可用来源"
    }
    var omittedWorkouts = 0
    var loadedAt = Date()
    var hasAnyData: Bool { !hrv.isEmpty || !restingHR.isEmpty || !sleep.isEmpty || !sessions.isEmpty || metrics.values.contains { !$0.isEmpty } }
}
@MainActor
protocol HealthDataProviding: AnyObject {
    func authorize() async throws
    func load(preferences: [String: String], onProgress: @escaping (HealthSnapshot) -> Void) async -> HealthSnapshot
    func observeChanges(_ action: @escaping () -> Void)
}

// All completion paths (including timeout and a late HealthKit callback) meet here.
@MainActor
final class HealthQueryTicket<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeout: Task<Void, Never>?
    var stop: (() -> Void)?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func startTimeout(seconds: Double = 20) {
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.finish(.failure(NSError(domain: "HappyBody", code: 408, userInfo: [NSLocalizedDescriptionKey: "读取超时，请解锁手机后重试。"])))
        }
    }
    func finish(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil
        stop?(); stop = nil
        continuation.resume(with: result)
    }
}

private struct HealthReadResult {
    let key: String
    var samples: [HKSample] = []
    var totals: [DayValue]? = nil
    var error: String? = nil
}
@MainActor
final class HealthService: HealthDataProviding {
    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    // Injection exercises failures and partial reads without accessing personal health records.
    var sampleReader: ((HKSampleType, Date, Date) async throws -> [HKSample])?
    var totalsReader: ((HealthMetric, Date, Date, Calendar) async throws -> [DayValue])?
    func observeChanges(_ action: @escaping () -> Void) {
        guard observers.isEmpty else { return }
        let types: [HKSampleType] = HealthMetric.allCases.compactMap { metric in
            if metric == .sleep { return HKObjectType.categoryType(forIdentifier: .sleepAnalysis) }
            return metric.identifier.flatMap { HKObjectType.quantityType(forIdentifier: $0) }
        } + [HKObjectType.workoutType()]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                completion()
                guard error == nil else { return }
                Task { @MainActor in action() }
            }
            observers.append(query); store.execute(query)
        }
    }
    private func query<Value>(_ make: (@escaping (Result<Value, Error>) -> Void) -> HKQuery) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let ticket = HealthQueryTicket<Value>(continuation)
            let query = make { result in Task { @MainActor in ticket.finish(result) } }
            ticket.stop = { [store] in store.stop(query) }
            ticket.startTimeout(); store.execute(query)
        }
    }
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }
    func authorize() async throws {
        guard Self.available else { throw NSError(domain: "HealthLens", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前设备不支持苹果健康。请在 iPhone 真机使用，或先查看示例。"] ) }
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]
        for metric in HealthMetric.allCases {
            if let identifier = metric.identifier, let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        // Completion means the authorization sheet completed, not that reads were granted.
        try await store.requestAuthorization(toShare: [], read: types)
    }
    private func read(_ type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        if let sampleReader { return try await sampleReader(type, start, end) }
        return try await query { finish in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictEndDate])
            return HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { finish(.failure(error)) } else { finish(.success(samples ?? [])) }
            }
        }
    }
    private func dailyTotals(_ metric: HealthMetric, from start: Date, to end: Date, calendar: Calendar) async throws -> [DayValue] {
        if let totalsReader { return try await totalsReader(metric, start, end, calendar) }
        guard let identifier = metric.identifier, let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        return try await query { finish in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: calendar.startOfDay(for: start), intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { finish(.failure(error)); return }
                var values: [DayValue] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let value = stats.sumQuantity()?.doubleValue(for: metric.unit), value.isFinite, value >= 0 {
                        values.append(DayValue(date: stats.startDate, value: value))
                    }
                }
                finish(.success(values))
            }
            return query
        }
    }
    private func source(_ s: HKSample) -> HealthSource {
        let device = s.device?.name ?? "设备未注明"
        let model = s.device?.model ?? ""
        return HealthSource(id: s.sourceRevision.source.bundleIdentifier + "|" + device + "|" + model, name: s.sourceRevision.source.name + " · " + device)
    }
    private func select(_ samples: [HKSample], key: String, preferences: [String: String], now: Date, calendar: Calendar) -> (samples: [HKSample], options: [HealthSource], chosen: String?) {
        let grouped = Dictionary(grouping: samples, by: { source($0) })
        let recent = calendar.date(byAdding: .day, value: -14, to: now)!
        let ranked = grouped.keys.sorted { a, b in
            let count: (HealthSource) -> Int = { s in Set((grouped[s] ?? []).filter { $0.startDate >= recent }.map { calendar.startOfDay(for: $0.startDate) }).count }
            let left = count(a), right = count(b)
            if left != right { return left > right }
            let latest: (HealthSource) -> Date = { grouped[$0]?.map(\.endDate).max() ?? .distantPast }
            if latest(a) != latest(b) { return latest(a) > latest(b) }
            return a.id < b.id
        }
        let chosen = ranked.first { $0.id == preferences[key] } ?? ranked.first
        return (chosen.flatMap { grouped[$0] } ?? [], ranked, chosen?.id)
    }
    private func fetch(_ key: String, start: Date, end: Date, calendar: Calendar) async -> HealthReadResult {
        do {
            if key == "workouts" { return HealthReadResult(key: key, samples: try await read(HKObjectType.workoutType(), from: start, to: end)) }
            guard let metric = HealthMetric(rawValue: key) else { return HealthReadResult(key: key) }
            if metric.cumulative { return HealthReadResult(key: key, totals: try await dailyTotals(metric, from: start, to: end, calendar: calendar)) }
            let type: HKSampleType = metric == .sleep ? HKObjectType.categoryType(forIdentifier: .sleepAnalysis)! : HKObjectType.quantityType(forIdentifier: metric.identifier!)!
            return HealthReadResult(key: key, samples: try await read(type, from: start, to: end))
        } catch {
            let title = HealthMetric(rawValue: key)?.title ?? "训练"
            return HealthReadResult(key: key, error: title + "：" + error.localizedDescription)
        }
    }
    func load(preferences: [String: String], onProgress: @escaping (HealthSnapshot) -> Void) async -> HealthSnapshot {
        let now = Date(), calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -60, to: calendar.startOfDay(for: now))!
        var snapshot = HealthSnapshot()
        // Read independently: a denied, failed or slow metric cannot discard other results.
        await withTaskGroup(of: HealthReadResult.self) { group in
            for key in HealthMetric.allCases.map(\.rawValue) + ["workouts"] {
                group.addTask { await self.fetch(key, start: start, end: now, calendar: calendar) }
            }
            for await result in group {
                snapshot.completedQueries += 1
                if let error = result.error { snapshot.readWarnings.append(error) }
                else if let totals = result.totals {
                    snapshot.metrics[result.key] = totals
                    snapshot.readCounts[result.key] = totals.count
                } else {
                    snapshot.readCounts[result.key] = result.samples.count
                    let selection = select(result.samples, key: result.key, preferences: preferences, now: now, calendar: calendar)
                    snapshot.sources[result.key] = selection.options; snapshot.selected[result.key] = selection.chosen
                    let samples = selection.samples
                    if result.key == "workouts" {
                        let sessions = samples.compactMap { s -> Session? in
                            guard let w = s as? HKWorkout else { return nil }
                            let descriptor = Self.describe(w.workoutActivityType)
                            return Session(id: w.uuid.uuidString, start: w.startDate, end: w.endDate, minutes: w.duration / 60, kind: descriptor.1, title: descriptor.0, source: source(w).name)
                        }
                        let clean = Aggregation.nonOverlapping(sessions)
                        snapshot.sessions = clean.sessions; snapshot.omittedWorkouts = clean.omitted
                    } else if let metric = HealthMetric(rawValue: result.key) {
                        if metric == .sleep {
                            let asleep = samples.filter { sample in
                                guard let value = sample as? HKCategorySample else { return false }
                                return [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains(value.value)
                            }
                            snapshot.sleep = Aggregation.sleepDays(asleep.filter { $0.endDate.timeIntervalSince($0.startDate) <= 48 * 3600 }.map { TimeSpan(start: $0.startDate, end: $0.endDate) }, calendar: calendar)
                        } else {
                            func daily(_ samples: [HKSample]) -> [DayValue] {
                                Aggregation.dailyMedian(samples.compactMap { sample in
                                    guard let value = sample as? HKQuantitySample else { return nil }
                                    return DayValue(date: value.startDate, value: value.quantity.doubleValue(for: metric.unit) * metric.multiplier)
                                }, calendar: calendar)
                            }
                            let points = daily(samples)
                            if metric == .hr { snapshot.restingHR = points }
                            else { snapshot.metrics[result.key] = points }
                            if metric == .hrv {
                                snapshot.hrv = daily(samples.filter {
                                    (5..<11).contains(calendar.component(.hour, from: $0.startDate)) && ($0.metadata?[HKMetadataKeyWasUserEntered] as? Bool != true)
                                })
                            }
                        }
                    }
                }
                snapshot.loadedAt = Date()
                onProgress(snapshot)
            }
        }
        return snapshot
    }
    static func describe(_ type: HKWorkoutActivityType) -> (String, SessionKind) {
        switch type {
        case .walking: return ("步行", .aerobic)
        case .running: return ("跑步", .aerobic)
        case .cycling: return ("骑行", .aerobic)
        case .swimming: return ("游泳", .aerobic)
        case .elliptical: return ("椭圆机", .aerobic)
        case .rowing: return ("划船", .aerobic)
        case .hiking: return ("徒步", .aerobic)
        case .dance, .cardioDance: return ("舞蹈", .aerobic)
        case .stairClimbing: return ("爬楼梯", .aerobic)
        case .traditionalStrengthTraining, .functionalStrengthTraining: return ("力量训练", .strength)
        case .yoga: return ("瑜伽", .other)
        case .pilates: return ("普拉提", .other)
        case .highIntensityIntervalTraining: return ("间歇训练（需核对类型）", .other)
        default: return ("其他训练", .other)
        }
    }
}
