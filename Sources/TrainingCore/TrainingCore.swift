import Foundation

public enum SessionKind: String, Codable, CaseIterable, Sendable { case aerobic, strength, other }
public enum Intensity: String, Codable, CaseIterable, Sendable { case unknown, light, moderate, vigorous }
public struct Session: Identifiable, Sendable {
    public let id: String
    public let start: Date
    public let end: Date
    public let minutes: Double
    public let kind: SessionKind
    public let title: String
    public let source: String
    public init(id: String, start: Date, end: Date, minutes: Double, kind: SessionKind, title: String, source: String) {
        self.id = id; self.start = start; self.end = end; self.minutes = minutes; self.kind = kind; self.title = title; self.source = source
    }
}
public struct SessionRating: Codable, Sendable {
    public var rpe: Int? = nil
    public var intensity: Intensity = .unknown
    public var majorMuscleGroups: Bool = false
    public init(rpe: Int? = nil, intensity: Intensity = .unknown, majorMuscleGroups: Bool = false) {
        self.rpe = rpe; self.intensity = intensity; self.majorMuscleGroups = majorMuscleGroups
    }
    public func load(minutes: Double) -> Double? {
        guard let rpe, (0...10).contains(rpe), minutes.isFinite, minutes > 0 else { return nil }
        return Double(rpe) * minutes
    }
}
public struct DayValue: Identifiable, Sendable {
    public let date: Date
    public let value: Double
    public var id: Date { date }
    public init(date: Date, value: Double) { self.date = date; self.value = value }
}
public struct TimeSpan: Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}
public enum Aggregation {
    public static func median(_ values: [Double]) -> Double? {
        let a = values.filter { $0.isFinite }.sorted()
        guard !a.isEmpty else { return nil }
        return a.count % 2 == 1 ? a[a.count / 2] : (a[a.count / 2 - 1] + a[a.count / 2]) / 2
    }
    public static func dailyMedian(_ values: [DayValue], calendar: Calendar) -> [DayValue] {
        Dictionary(grouping: values.filter { $0.value.isFinite && $0.value > 0 }, by: { calendar.startOfDay(for: $0.date) })
            .compactMap { day, points in median(points.map(\.value)).map { DayValue(date: day, value: $0) } }.sorted { $0.date < $1.date }
    }
    public static func merged(_ spans: [TimeSpan]) -> [TimeSpan] {
        var result: [TimeSpan] = []
        for span in spans.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            if let last = result.last, span.start <= last.end {
                result[result.count - 1].end = max(last.end, span.end)
            } else { result.append(span) }
        }
        return result
    }
    // Noon-to-noon sleep windows, attributed to the date of the closing noon.
    // Calendar arithmetic preserves daylight-saving boundaries; durations use real elapsed time.
    public static func sleepDays(_ spans: [TimeSpan], calendar: Calendar) -> [DayValue] {
        var totals: [Date: Double] = [:]
        for span in merged(spans) {
            var cursor = span.start
            while cursor < span.end {
                let day = calendar.startOfDay(for: cursor)
                let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
                let closingNoon = cursor < noon ? noon : calendar.date(byAdding: .day, value: 1, to: noon)!
                let end = min(span.end, closingNoon)
                totals[calendar.startOfDay(for: closingNoon), default: 0] += end.timeIntervalSince(cursor) / 3600
                cursor = end
            }
        }
        return totals.map { DayValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }
    // Conservative duplicate/overlap policy within the user's chosen workout source.
    public static func nonOverlapping(_ sessions: [Session]) -> (sessions: [Session], omitted: Int) {
        var out: [Session] = []; var omitted = 0
        for s in sessions.filter({ $0.minutes.isFinite && $0.minutes > 0 && $0.end > $0.start }).sorted(by: {
            $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start
        }) {
            if let last = out.last, s.start < last.end { omitted += 1 } else { out.append(s) }
        }
        return (out, omitted)
    }
}
public struct CheckIn: Codable, Sendable {
    public var date: Date
    public var fatigue: Int
    public var soreness: Int
    public var feelsUnwell: Bool
    public var warningSymptoms: Bool
    public init(date: Date = Date(), fatigue: Int = 2, soreness: Int = 1, feelsUnwell: Bool = false, warningSymptoms: Bool = false) {
        self.date = date; self.fatigue = fatigue; self.soreness = soreness; self.feelsUnwell = feelsUnwell; self.warningSymptoms = warningSymptoms
    }
}
public enum Plan: String, Codable, CaseIterable, Sendable { case easy, aerobic, strength, rest }
public enum AdviceLevel: String, Sendable { case checkIn, insufficient, maintain, ease, rest, medical }
public struct Advice: Sendable {
    public let level: AdviceLevel
    public let title: String
    public let action: String
    public let evidence: [String]
    public let confidence: String
}
public struct Signal: Sendable {
    public let current: Double?
    public let baseline: Double?
    public let baselineDays: Int
    public let recentDays: Int
    public let unusual: Bool
}
public struct RecoveryInput: Sendable {
    public var hrv: [DayValue]
    public var sessions: [Session]
    public var ratings: [String: SessionRating]
    public var restingHR: [DayValue]
    public var sleep: [DayValue]
    public var checkIn: CheckIn?
    public var plan: Plan
    public var beginner: Bool
    public var now: Date
    public var calendar: Calendar
    public init(hrv: [DayValue] = [], sessions: [Session] = [], ratings: [String: SessionRating] = [:], restingHR: [DayValue] = [], sleep: [DayValue] = [], checkIn: CheckIn? = nil, plan: Plan = .easy, beginner: Bool = true, now: Date = Date(), calendar: Calendar = .current) {
        self.hrv = hrv; self.sessions = sessions; self.ratings = ratings; self.restingHR = restingHR; self.sleep = sleep; self.checkIn = checkIn; self.plan = plan; self.beginner = beginner; self.now = now; self.calendar = calendar
    }
}
public enum TrainingEngine {
    public static let version = "1.1.1"
    // Exploratory product rule, not a clinically validated HRV training protocol.
    // 28 baseline days excluding current/recent 7; at least 14 observed baseline days.
    // Median and 1.4826*MAD on log(SDNN); sustained signal needs >=2 of 3 recent days
    // and a current-day reading. No SDNN -> RMSSD conversion.
    public static func signal(_ points: [DayValue], lower: Bool, logTransform: Bool, now: Date, calendar: Calendar) -> Signal {
        let today = calendar.startOfDay(for: now)
        let day = { (n: Int) in calendar.date(byAdding: .day, value: n, to: today)! }
        let daily = Aggregation.dailyMedian(points.filter { $0.date <= now }, calendar: calendar)
        let base = daily.filter { $0.date >= day(-35) && $0.date < day(-7) }
        let recent = daily.filter { $0.date >= day(-2) && $0.date <= today }
        let current = daily.first { $0.date == today }?.value
        let transform: (Double) -> Double = { logTransform ? log($0) : $0 }
        let baseline = Aggregation.median(base.map(\.value))
        guard base.count >= 14, let center = Aggregation.median(base.map { transform($0.value) }), current != nil, recent.count >= 2 else {
            return Signal(current: current, baseline: baseline, baselineDays: base.count, recentDays: recent.count, unusual: false)
        }
        let mad = Aggregation.median(base.map { abs(transform($0.value) - center) }) ?? 0
        // A zero MAD is not evidence of abnormal physiology. Refuse a noisy threshold.
        guard mad > 0.000001 else { return Signal(current: current, baseline: baseline, baselineDays: base.count, recentDays: recent.count, unusual: false) }
        let boundary = center + (lower ? -1 : 1) * 2 * 1.4826 * mad
        let outlier: (Double) -> Bool = { lower ? transform($0) < boundary : transform($0) > boundary }
        let unusual = outlier(current!) && recent.filter { outlier($0.value) }.count >= 2
        return Signal(current: current, baseline: baseline, baselineDays: base.count, recentDays: recent.count, unusual: unusual)
    }
    public static func advice(_ input: RecoveryInput) -> Advice {
        let c = input.calendar; let today = c.startOfDay(for: input.now)
        let check = input.checkIn.flatMap { c.isDate($0.date, inSameDayAs: today) && $0.date <= input.now && (1...5).contains($0.fatigue) && (1...5).contains($0.soreness) ? $0 : nil }
        guard let check else {
            var evidence: [String] = []
            if let sleep = input.sleep.last(where: { c.isDate($0.date, inSameDayAs: today) && $0.value.isFinite && $0.value > 0 }) {
                evidence.append(String(format: "最近睡眠窗口 %.1f 小时；漏戴可能低估。", sleep.value))
            } else { evidence.append("没有今日睡眠窗口记录。") }
            let hrv = signal(input.hrv, lower: true, logTransform: true, now: input.now, calendar: c)
            let hr = signal(input.restingHR, lower: false, logTransform: false, now: input.now, calendar: c)
            evidence.append("晨间 HRV 基线 \(hrv.baselineDays)/28 天；静息心率基线 \(hr.baselineDays)/28 天。")
            if hrv.unusual || hr.unusual { evidence.append("检测到个人趋势持续偏离，需结合今天的感受再判断。") }
            let week = Weekly.summarize(input.sessions, ratings: input.ratings, now: input.now, calendar: c)
            evidence.append("近 7 天 \(week.totalSessions) 次训练，\(week.ratedSessions) 次已评分。")
            let hasData = !input.hrv.isEmpty || !input.restingHR.isEmpty || !input.sleep.isEmpty || !input.sessions.isEmpty
            return Advice(level: .checkIn, title: hasData ? "数据已更新，补充今天的感受" : "先读取数据并记录今天的感受", action: "数据摘要会随读取更新。还需确认今天的疲劳、酸痛和身体不适，才能给出个体训练调整；昨天的自评不能代替今天。", evidence: evidence, confidence: "数据摘要已计算 · 今日自评待完成")
        }
        if check.warningSymptoms { return Advice(level: .medical, title: "暂停锻炼，优先寻求医疗帮助", action: "胸痛、晕厥或明显异常气短不应由训练算法判断。若症状正在发生、严重或持续，请立即联系当地急救服务。", evidence: ["你报告了需优先处理的症状；其他指标不能抵消这一信息。"], confidence: "由症状触发，不作诊断") }
        if check.feelsUnwell { return Advice(level: .rest, title: "今天优先休息", action: "身体不适或发热时，先暂停原定训练；症状持续、加重或令你担忧时请咨询医生。", evidence: ["你报告今天身体不适。"], confidence: "依据今日自评") }
        let hrv = signal(input.hrv, lower: true, logTransform: true, now: input.now, calendar: c)
        let hr = signal(input.restingHR, lower: false, logTransform: false, now: input.now, calendar: c)
        let sleep = input.sleep.last { c.isDate($0.date, inSameDayAs: today) && $0.value.isFinite && $0.value > 0 }
        var evidence = ["HRV 基线 \(hrv.baselineDays)/28 个记录日；静息心率基线 \(hr.baselineDays)/28 个记录日。"]
        let load = Weekly.summarize(input.sessions, ratings: input.ratings, now: input.now, calendar: c)
        evidence.append("近 7 天已评分训练负荷 \(Int(load.recordedLoad)) AU（\(load.ratedSessions)/\(load.totalSessions) 次）；负荷仅供参考，不推算恢复时长。")
        if hrv.unusual { evidence.append("同一来源晨间 SDNN 持续低于个人统计范围；仅作为探索性趋势信号。") }
        if hr.unusual { evidence.append("静息心率持续高于个人统计范围。") }
        let shortSleep = (sleep?.value ?? 99) < 7
        if let sleep { evidence.append(String(format: "最近睡眠窗口记录 %.1f 小时；漏戴可能低估。", sleep.value)) } else { evidence.append("没有最近睡眠窗口的数据，不能推断已经充分休息。") }
        if check.fatigue >= 4 || check.soreness >= 4 {
            evidence.append("今日疲劳或酸痛自评较高（4–5/5）。")
            return Advice(level: .rest, title: "优先恢复，调整今天的训练", action: "暂停今天的高强度或较重力量训练。可以休息；若没有不适，也可选择舒适的轻松活动。不要为了周目标补量。", evidence: evidence, confidence: "主要依据主观疲劳／酸痛")
        }
        let physiological = [hrv.unusual, hr.unusual].filter { $0 }.count
        if physiological >= 2 || (physiological >= 1 && (shortSleep || check.fatigue >= 3)) || (shortSleep && check.fatigue >= 3) {
            return Advice(level: .ease, title: "今天把强度降一档", action: "将原定训练换为轻松活动或休息，明天重新评估。多项信息共同提示需要谨慎，并不代表已诊断疲劳或疾病。", evidence: evidence, confidence: "多信号启发式规则 · 尚未经前瞻验证")
        }
        if input.plan == .rest { return Advice(level: .maintain, title: "按计划休息", action: "保留休息日，无需因为数据平稳而加练。", evidence: evidence, confidence: "尊重原定计划") }
        if physiological > 0 || shortSleep {
            return Advice(level: .ease, title: "先轻松开始，今天不额外加量", action: "有单项信息值得复核。先确认佩戴和测量条件，结合热身后的感受决定是否继续；若不舒服就停止。", evidence: evidence, confidence: "单项信号不足以判断恢复状态")
        }
        let enough = hrv.current != nil && hr.current != nil && hrv.baselineDays >= 14 && hr.baselineDays >= 14 && sleep != nil
        let action: String
        switch input.plan {
        case .easy: action = input.beginner ? "可考虑 10–15 分钟舒适步行，保持能轻松交谈；不适时停止。" : "可按习惯安排轻松步行或活动，保持舒适，不追求负荷分数。"
        case .aerobic: action = input.beginner ? "从短时、舒适的有氧活动开始，逐步建立习惯；不要为凑足 150 分钟突然补量。" : "可按已适应的有氧计划进行；热身后结合感受调整，不因指标平稳额外加量。"
        case .strength: action = "可考虑已熟悉、动作可控的力量练习，覆盖主要肌群；不自动增加重量、组数或练到力竭。"
        case .rest: action = "按计划休息。"
        }
        return Advice(level: enough ? .maintain : .insufficient, title: enough ? "可以考虑维持原计划" : "数据不足，按感受保守安排", action: action, evidence: evidence, confidence: enough ? "未触发保守调整规则，不等于医疗许可" : "仅依据今日自评与一般活动建议")
    }
}
public struct WeekSummary: Sendable {
    public let equivalentMinutes: Double
    public let strengthDays: Int
    public let unknownAerobicSessions: Int
    public let recordedLoad: Double
    public let ratedSessions: Int
    public let totalSessions: Int
}
public enum Weekly {
    public static func summarize(_ sessions: [Session], ratings: [String: SessionRating], now: Date, calendar: Calendar) -> WeekSummary {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today)!
        let valid = sessions.filter { $0.start >= start && $0.end <= now && $0.minutes.isFinite && $0.minutes > 0 }
        var minutes = 0.0, load = 0.0, rated = 0, unknown = 0; var strength: Set<Date> = []
        for s in valid {
            let r = ratings[s.id] ?? SessionRating()
            if let l = r.load(minutes: s.minutes) { load += l; rated += 1 }
            if s.kind == .aerobic {
                switch r.intensity { case .moderate: minutes += s.minutes; case .vigorous: minutes += s.minutes * 2; case .unknown: unknown += 1; case .light: break }
            }
            if s.kind == .strength && r.majorMuscleGroups && [.moderate, .vigorous].contains(r.intensity) { strength.insert(calendar.startOfDay(for: s.start)) }
        }
        return WeekSummary(equivalentMinutes: minutes, strengthDays: strength.count, unknownAerobicSessions: unknown, recordedLoad: load, ratedSessions: rated, totalSessions: valid.count)
    }
}


public struct JournalEntry: Codable, Identifiable, Sendable {
    public var id: Date { checkIn.date }
    public var checkIn: CheckIn
    public var tags: [String]
    public var note: String
    public init(checkIn: CheckIn, tags: [String] = [], note: String = "") {
        self.checkIn = checkIn; self.tags = tags; self.note = note
    }
}
public struct PrivateNotes: Codable {
    public var ratings: [String: SessionRating] = [:]
    public var checkIn: CheckIn? = nil
    public var journal: [JournalEntry]? = nil
    public init() {}
    public var entries: [JournalEntry] {
        var values = journal ?? []
        if let checkIn, !values.contains(where: { Calendar.current.isDate($0.checkIn.date, inSameDayAs: checkIn.date) }) {
            values.append(JournalEntry(checkIn: checkIn))
        }
        return values.sorted { $0.checkIn.date > $1.checkIn.date }
    }
    public mutating func record(_ entry: JournalEntry, calendar: Calendar = .current) {
        var history = entries.filter { !calendar.isDate($0.checkIn.date, inSameDayAs: entry.checkIn.date) }
        history.append(entry)
        journal = history.sorted { $0.checkIn.date > $1.checkIn.date }
        checkIn = journal?.first?.checkIn
    }
}
