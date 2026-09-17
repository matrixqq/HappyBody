import Foundation
import SwiftUI
#if canImport(TrainingCore)
import TrainingCore
#endif

struct PrivateNotes: Codable {
    var ratings: [String: SessionRating] = [:]
    var checkIn: CheckIn? = nil
}
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
    @Published var plan: Plan = .easy
    @Published var beginner = true
    @Published var now = Date()
    @Published var adultAcknowledged = UserDefaults.standard.bool(forKey: "adultAcknowledged") { didSet { UserDefaults.standard.set(adultAcknowledged, forKey: "adultAcknowledged") } }
    @Published var healthSheetCompleted = UserDefaults.standard.bool(forKey: "healthSheetCompleted") { didSet { UserDefaults.standard.set(healthSheetCompleted, forKey: "healthSheetCompleted") } }
    private let health = HealthService()
    private var disk: NotesStore?
    private var preferences: [String: String] { UserDefaults.standard.dictionary(forKey: "sourceChoices") as? [String: String] ?? [:] }
    init() {
        do { let disk = try NotesStore(); notes = try disk.load(); self.disk = disk }
        catch { message = "本机记录暂时无法读取：\(error.localizedDescription)。本次改动不会覆盖原记录。" }
    }
    var advice: Advice { TrainingEngine.advice(RecoveryInput(hrv: snapshot.hrv, sessions: snapshot.sessions, ratings: notes.ratings, restingHR: snapshot.restingHR, sleep: snapshot.sleep, checkIn: notes.checkIn, plan: plan, beginner: beginner, now: Date())) }
    var week: WeekSummary { Weekly.summarize(snapshot.sessions, ratings: notes.ratings, now: Date(), calendar: .current) }
    func connect() async {
        guard adultAcknowledged, !busy else { return }
        busy = true; message = nil
        do {
            try await health.authorize(); healthSheetCompleted = true
            let fresh = try await health.load(preferences: preferences)
            if demo { try restoreNotes() }
            demo = false; snapshot = fresh; now = Date()
            if !fresh.hasAnyData { message = "暂未读取到记录：可能没有数据或未允许读取。可在「健康」App 的应用权限中检查；App 无法区分这两种情况。" }
        } catch { message = "健康数据读取未完成：\(error.localizedDescription)" }
        busy = false
    }
    func refresh() async {
        now = Date()
        guard healthSheetCompleted, !demo, !busy, adultAcknowledged else { return }
        busy = true; message = nil
        do { snapshot = try await health.load(preferences: preferences) }
        catch { snapshot = HealthSnapshot(); message = "刷新失败，旧健康数据已从当前分析移除：\(error.localizedDescription)" }
        busy = false
    }
    func chooseSource(key: String, id: String) async {
        guard !demo else { return }
        var choices = preferences; choices[key] = id
        UserDefaults.standard.set(choices, forKey: "sourceChoices")
        await refresh()
    }
    func rate(_ session: Session, rating: SessionRating) {
        var candidate = notes; candidate.ratings[session.id] = rating; persist(candidate)
    }
    func checkIn(_ value: CheckIn) { var candidate = notes; candidate.checkIn = value; now = Date(); persist(candidate) }
    private func persist(_ candidate: PrivateNotes) {
        if demo { notes = candidate; return }
        do {
            guard let disk else { throw NSError(domain: "HealthLens", code: 2, userInfo: [NSLocalizedDescriptionKey: "本机存储不可用，未保存更改。请解锁设备并重新打开 App。"] ) }
            try disk.save(candidate); notes = candidate
        } catch { message = "保存失败：\(error.localizedDescription)" }
    }
    private func restoreNotes() throws { notes = try disk?.load() ?? PrivateNotes() }
    func clearNotes() { persist(PrivateNotes()) }
    func leaveDemo() {
        do { try restoreNotes(); demo = false; snapshot = HealthSnapshot(); now = Date() }
        catch { message = "无法恢复本机记录：\(error.localizedDescription)" }
    }
    func showDemo() {
        guard !busy else { return }
        demo = true; message = nil; now = Date(); notes = PrivateNotes(); snapshot = HealthSnapshot()
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
        notes.checkIn = CheckIn(date: now, fatigue: 3, soreness: 2)
    }
}
