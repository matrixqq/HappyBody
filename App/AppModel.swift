import Foundation
import SwiftUI
#if canImport(TrainingCore)
import TrainingCore
#endif

final class NotesStore {
    private let url: URL
    init() throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("HealthLens", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        url = directory.appendingPathComponent("private-notes.json")
    }
    func load() throws -> PrivateNotes {
        guard FileManager.default.fileExists(atPath: url.path) else { return PrivateNotes() }
        return try JSONDecoder().decode(PrivateNotes.self, from: Data(contentsOf: url))
    }
    func save(_ notes: PrivateNotes) throws {
        try JSONEncoder().encode(notes).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot = HealthSnapshot()
    @Published var notes = PrivateNotes()
    @Published var demo = false
    @Published var busy = false
    @Published var message: String?
    @Published var plan: Plan = Plan(rawValue: UserDefaults.standard.string(forKey: "trainingPlan") ?? "easy") ?? .easy { didSet { if !demo { UserDefaults.standard.set(plan.rawValue, forKey: "trainingPlan") } } }
    @Published var beginner = UserDefaults.standard.object(forKey: "beginner") as? Bool ?? true { didSet { if !demo { UserDefaults.standard.set(beginner, forKey: "beginner") } } }
    @Published var now = Date()
    @Published var adultAcknowledged = UserDefaults.standard.bool(forKey: "adultAcknowledged") { didSet { UserDefaults.standard.set(adultAcknowledged, forKey: "adultAcknowledged") } }
    @Published var healthSheetCompleted = UserDefaults.standard.bool(forKey: "healthSheetCompleted") { didSet { UserDefaults.standard.set(healthSheetCompleted, forKey: "healthSheetCompleted") } }
    private let health: HealthDataProviding
    @Published var syncStatus = "尚未读取健康数据"
    private var pendingRefresh = false
    private var observerRefresh: Task<Void, Never>?
    private var observing = false
    private var disk: NotesStore?
    private var preferences: [String: String] { UserDefaults.standard.dictionary(forKey: "sourceChoices") as? [String: String] ?? [:] }
    init(health: HealthDataProviding? = nil) {
        self.health = health ?? HealthService()
        do { let disk = try NotesStore(); notes = try disk.load(); self.disk = disk }
        catch { message = "本机记录暂时无法读取：\(error.localizedDescription)。本次改动不会覆盖原记录。" }
    }
    var advice: Advice {
        let result = TrainingEngine.advice(RecoveryInput(hrv: snapshot.hrv, sessions: snapshot.sessions, ratings: notes.ratings, restingHR: snapshot.restingHR, sleep: snapshot.sleep, checkIn: notes.checkIn, plan: plan, beginner: beginner, now: now))
        if busy && result.level != .medical && result.level != .rest {
            return Advice(level: .insufficient, title: "正在更新数据与建议", action: "已读取的指标会逐项显示，读取结束后重新评估训练建议。", evidence: [syncStatus], confidence: "读取进行中，不根据不完整结果建议加练")
        }
        return result
    }
    var week: WeekSummary { Weekly.summarize(snapshot.sessions, ratings: notes.ratings, now: now, calendar: .current) }
    private func observe() {
        guard !observing else { return }
        observing = true
        health.observeChanges { [weak self] in
            guard let self, !self.demo else { return }
            self.observerRefresh?.cancel()
            self.observerRefresh = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                await self?.refresh()
            }
        }
    }
    func connect() async {
        guard adultAcknowledged, !busy else { return }
        busy = true; message = nil; syncStatus = "等待健康授权"
        do {
            // Do not leave example/previous readings looking like a successful real read.
            if demo { try restoreNotes() }
            demo = false; snapshot = HealthSnapshot()
            try await health.authorize(); healthSheetCompleted = true
            observe()
            await readSnapshot()
        } catch { syncStatus = "授权流程未完成"; message = "健康数据读取未完成：\(error.localizedDescription)" }
        busy = false
        await drainRefresh()
    }
    private func readSnapshot() async {
        snapshot = HealthSnapshot(); now = Date(); syncStatus = "正在读取健康数据"
        let fresh = await health.load(preferences: preferences) { [weak self] partial in
            guard let self else { return }
            self.snapshot = partial; self.now = Date()
            self.syncStatus = "已读取 \(partial.completedQueries)/\(HealthSnapshot.queryCount) 项 · \(partial.summary)"
        }
        snapshot = fresh; now = Date()
        if !fresh.readWarnings.isEmpty { syncStatus = "部分读取完成 · " + fresh.summary }
        else if !fresh.hasAnyData { syncStatus = "读取完成，未返回记录" }
        else { syncStatus = "已更新 · " + fresh.summary }
    }
    private func drainRefresh() async {
        guard pendingRefresh else { return }
        pendingRefresh = false
        await refresh()
    }
    func refresh() async {
        now = Date()
        guard healthSheetCompleted, !demo, adultAcknowledged else { return }
        if busy { pendingRefresh = true; return }
        busy = true; message = nil
        observe()
        await readSnapshot()
        busy = false
        await drainRefresh()
    }
    func chooseSource(key: String, id: String) async {
        guard !demo else { return }
        var choices = preferences; choices[key] = id
        UserDefaults.standard.set(choices, forKey: "sourceChoices")
        await refresh()
    }
    @discardableResult func rate(_ session: Session, rating: SessionRating) -> Bool {
        var candidate = notes; candidate.ratings[session.id] = rating; return persist(candidate)
    }
    @discardableResult func checkIn(_ value: CheckIn, tags: [String] = [], note: String = "") -> Bool { var candidate = notes; candidate.record(JournalEntry(checkIn: value, tags: tags, note: note)); now = Date(); return persist(candidate) }
    @discardableResult private func persist(_ candidate: PrivateNotes) -> Bool {
        if demo { notes = candidate; return true }
        do {
            guard let disk else { throw NSError(domain: "HealthLens", code: 2, userInfo: [NSLocalizedDescriptionKey: "本机存储不可用，未保存更改。请解锁设备并重新打开 App。"] ) }
            try disk.save(candidate); notes = candidate; return true
        } catch { message = "保存失败：\(error.localizedDescription)"; return false }
    }
    private func restoreNotes() throws {
        notes = try disk?.load() ?? PrivateNotes()
        plan = Plan(rawValue: UserDefaults.standard.string(forKey: "trainingPlan") ?? "easy") ?? .easy
        beginner = UserDefaults.standard.object(forKey: "beginner") as? Bool ?? true
    }
    func clearNotes() { persist(PrivateNotes()) }
    func leaveDemo() {
        do { try restoreNotes(); demo = false; snapshot = HealthSnapshot(); now = Date(); syncStatus = "已退出示例，正在读取"; Task { await refresh() } }
        catch { message = "无法恢复本机记录：\(error.localizedDescription)" }
    }
    func showDemo() {
        guard !busy else { return }
        demo = true; syncStatus = "示例数据 · 非真实读取"; message = nil; now = Date(); notes = PrivateNotes(); snapshot = HealthSnapshot()
        let calendar = Calendar.current, today = calendar.startOfDay(for: now)
        for i in -50...0 {
            let day = calendar.date(byAdding: .day, value: i, to: today)!
            // Day timestamps for fixture data keep the current day's observation available.
            snapshot.hrv.append(DayValue(date: day, value: 48 + sin(Double(i)) * 5 - (i >= -2 ? 15 : 0)))
            snapshot.restingHR.append(DayValue(date: day, value: 59 + sin(Double(i)) * 2 + (i >= -2 ? 7 : 0)))
            snapshot.sleep.append(DayValue(date: day, value: i >= -2 ? 6.2 : 7.5))
        }
        for i in [1, 2, 4, 6] {
            let start = calendar.date(byAdding: .day, value: -i, to: today)!.addingTimeInterval(18 * 3600)
            let strength = i == 2 || i == 6
            let session = Session(id: "demo-\(i)", start: start, end: start.addingTimeInterval(1800), minutes: 30, kind: strength ? .strength : .aerobic, title: strength ? "力量训练" : "快走", source: "模拟记录")
            snapshot.sessions.append(session); notes.ratings[session.id] = SessionRating(rpe: 4, intensity: .moderate, majorMuscleGroups: strength)
        }
        for metric in HealthMetric.allCases where ![HealthMetric.hrv, .hr, .sleep].contains(metric) {
            let base: Double
            switch metric { case .steps: base = 7200; case .energy: base = 360; case .floors: base = 5; case .vo2: base = 38; case .respiration: base = 14; case .oxygen: base = 97; case .wrist: base = 35.8; case .weight: base = 68; case .bmi: base = 22.5; case .fat: base = 22; case .lean: base = 53; default: base = 1 }
            snapshot.metrics[metric.rawValue] = (-27...0).map { offset in
                DayValue(date: calendar.date(byAdding: .day, value: offset, to: today)!, value: base * (1 + sin(Double(offset)) * 0.02))
            }
        }
        for offset in [-4, -2, 0] {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!
            notes.record(JournalEntry(checkIn: CheckIn(date: date, fatigue: offset == 0 ? 3 : 2, soreness: 2), tags: offset == 0 ? ["晚睡"] : ["规律作息"], note: "示例记录，不代表你的实际状态。"))
        }
    }
}
