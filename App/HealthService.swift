import Foundation
import HealthKit
#if canImport(TrainingCore)
import TrainingCore
#endif

struct HealthSource: Identifiable, Hashable {
    let id: String
    let name: String
}
struct HealthSnapshot {
    var hrv: [DayValue] = []
    var restingHR: [DayValue] = []
    var sleep: [DayValue] = []
    var sessions: [Session] = []
    var sources: [String: [HealthSource]] = [:]
    var selected: [String: String] = [:]
    var omittedWorkouts = 0
    var loadedAt = Date()
    var hasAnyData: Bool { !hrv.isEmpty || !restingHR.isEmpty || !sleep.isEmpty || !sessions.isEmpty }
}
@MainActor
final class HealthService {
    private let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }
    func authorize() async throws {
        guard Self.available else { throw NSError(domain: "HealthLens", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前设备不支持苹果健康。请在 iPhone 真机使用，或先查看示例。"] ) }
        let types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]
        // Completion means the authorization sheet completed, not that reads were granted.
        try await store.requestAuthorization(toShare: [], read: types)
    }
    private func read(_ type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictEndDate])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
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
    func load(preferences: [String: String]) async throws -> HealthSnapshot {
        let now = Date(), calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -60, to: calendar.startOfDay(for: now))!
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let hrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let hrvRaw = try await read(hrvType, from: start, to: now)
        let hrRaw = try await read(hrType, from: start, to: now)
        let sleepRaw = try await read(sleepType, from: start, to: now)
        let workoutRaw = try await read(HKObjectType.workoutType(), from: start, to: now)
        var snapshot = HealthSnapshot()
        func selected(_ values: [HKSample], key: String) -> [HKSample] {
            let result = select(values, key: key, preferences: preferences, now: now, calendar: calendar)
            snapshot.sources[key] = result.options
            snapshot.selected[key] = result.chosen
            return result.samples
        }
        let morning = hrvRaw.filter { sample in
            let hour = calendar.component(.hour, from: sample.startDate)
            return (5..<11).contains(hour) && (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool != true)
        }
        snapshot.hrv = Aggregation.dailyMedian(selected(morning, key: "hrv").compactMap { s in
            guard let s = s as? HKQuantitySample else { return nil }
            return DayValue(date: s.startDate, value: s.quantity.doubleValue(for: .secondUnit(with: .milli)))
        }, calendar: calendar)
        snapshot.restingHR = Aggregation.dailyMedian(selected(hrRaw, key: "hr").compactMap { s in
            guard let s = s as? HKQuantitySample else { return nil }
            return DayValue(date: s.startDate, value: s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
        }, calendar: calendar)
        let asleep = sleepRaw.filter { sample in
            guard let s = sample as? HKCategorySample else { return false }
            return [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains(s.value)
        }
        snapshot.sleep = Aggregation.sleepDays(selected(asleep, key: "sleep").filter { $0.endDate.timeIntervalSince($0.startDate) <= 48 * 3600 }.map { TimeSpan(start: $0.startDate, end: $0.endDate) }, calendar: calendar)
        let sessions = selected(workoutRaw, key: "workouts").compactMap { s -> Session? in
            guard let w = s as? HKWorkout else { return nil }
            let descriptor = Self.describe(w.workoutActivityType)
            return Session(id: w.uuid.uuidString, start: w.startDate, end: w.endDate, minutes: w.duration / 60, kind: descriptor.1, title: descriptor.0, source: source(w).name)
        }
        let clean = Aggregation.nonOverlapping(sessions)
        snapshot.sessions = clean.sessions; snapshot.omittedWorkouts = clean.omitted; snapshot.loadedAt = now
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
