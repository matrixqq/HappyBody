import XCTest
@testable import TrainingCore

final class TrainingCoreTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    var now: Date { ISO8601DateFormatter().date(from: "2026-09-11T12:00:00Z")! }
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))! }
    func values(low: Bool = false, high: Bool = false) -> [DayValue] {
        (-40...0).map { i in DayValue(date: day(i), value: 50 + Double(abs(i) % 5) + (i >= -2 ? (low ? -25 : high ? 25 : 0) : 0)) }
    }
    func input(check: CheckIn? = nil) -> RecoveryInput {
        RecoveryInput(hrv: values(), restingHR: values(), sleep: [DayValue(date: day(0), value: 8)], checkIn: check ?? CheckIn(date: now), now: now, calendar: calendar)
    }
    func testMissingCheckInNeverProducesMaintainAdvice() {
        var i = input(); i.checkIn = nil
        XCTAssertEqual(TrainingEngine.advice(i).level, .checkIn)
        i.checkIn = CheckIn(date: day(-1))
        XCTAssertEqual(TrainingEngine.advice(i).level, .checkIn)
    }
    func testWarningSymptomsOverrideAllPositiveData() {
        let i = input(check: CheckIn(date: now, warningSymptoms: true))
        XCTAssertEqual(TrainingEngine.advice(i).level, .medical)
    }
    func testIllnessAndFatiguePrioritizeRest() {
        XCTAssertEqual(TrainingEngine.advice(input(check: CheckIn(date: now, feelsUnwell: true))).level, .rest)
        XCTAssertEqual(TrainingEngine.advice(input(check: CheckIn(date: now, fatigue: 5))).level, .rest)
    }
    func testPartialOrMissingDataDoesNotImplyRecovered() {
        var i = input(); i.hrv = []; i.restingHR = []; i.sleep = []
        XCTAssertEqual(TrainingEngine.advice(i).level, .insufficient)
        XCTAssertFalse(TrainingEngine.signal([], lower: true, logTransform: true, now: now, calendar: calendar).unusual)
    }
    func testSustainedSignalsNeedCurrentDayAndHistory() {
        XCTAssertTrue(TrainingEngine.signal(values(low: true), lower: true, logTransform: true, now: now, calendar: calendar).unusual)
        XCTAssertFalse(TrainingEngine.signal(values(low: true).filter { $0.date < day(0) }, lower: true, logTransform: true, now: now, calendar: calendar).unusual)
        XCTAssertFalse(TrainingEngine.signal(Array(values(low: true).suffix(8)), lower: true, logTransform: true, now: now, calendar: calendar).unusual)
        let constant = (-40...0).map { DayValue(date: day($0), value: $0 < -2 ? 50 : 10) }
        XCTAssertFalse(TrainingEngine.signal(constant, lower: true, logTransform: true, now: now, calendar: calendar).unusual)
    }
    func testOneOffHrvDropDoesNotCountAsSustained() {
        var points = values(); points[points.count - 1] = DayValue(date: day(0), value: 10)
        XCTAssertFalse(TrainingEngine.signal(points, lower: true, logTransform: true, now: now, calendar: calendar).unusual)
    }
    func testMultipleSignalsEaseAndRestPlanDoesNotAddTraining() {
        var i = input(); i.hrv = values(low: true); i.restingHR = values(high: true)
        XCTAssertEqual(TrainingEngine.advice(i).level, .ease)
        i = input(); i.plan = .rest
        XCTAssertEqual(TrainingEngine.advice(i).title, "按计划休息")
    }
    func testSleepUnionAcrossMidnightAndStages() {
        let start = day(-1).addingTimeInterval(23 * 3600), end = day(0).addingTimeInterval(7 * 3600)
        let spans = [TimeSpan(start: start, end: end), TimeSpan(start: start, end: start.addingTimeInterval(4 * 3600)), TimeSpan(start: start.addingTimeInterval(3 * 3600), end: end)]
        let sleep = Aggregation.sleepDays(spans, calendar: calendar)
        XCTAssertEqual(sleep.count, 1); XCTAssertEqual(sleep[0].date, day(0)); XCTAssertEqual(sleep[0].value, 8, accuracy: 0.0001)
    }
    func testSleepUsesElapsedHoursAcrossDaylightSaving() {
        var c = calendar; c.timeZone = TimeZone(identifier: "America/New_York")!
        let formatter = ISO8601DateFormatter()
        let spans = [TimeSpan(start: formatter.date(from: "2026-03-07T23:00:00-05:00")!, end: formatter.date(from: "2026-03-08T07:00:00-04:00")!)]
        XCTAssertEqual(Aggregation.sleepDays(spans, calendar: c).first!.value, 7, accuracy: 0.001)
    }
    func testUnknownIntensityAndRpeAreNotZeroObservations() {
        let s = session("one", offset: -1)
        let result = Weekly.summarize([s], ratings: [:], now: now, calendar: calendar)
        XCTAssertEqual(result.unknownAerobicSessions, 1); XCTAssertEqual(result.ratedSessions, 0); XCTAssertEqual(result.equivalentMinutes, 0)
        XCTAssertNil(SessionRating().load(minutes: 30))
        XCTAssertNil(SessionRating(rpe: 11).load(minutes: 30))
        XCTAssertEqual(SessionRating(rpe: 0).load(minutes: 30), 0)
    }
    func testWeeklyEquivalentAndDistinctStrengthDays() {
        let sessions = [session("a", offset: -1), session("b", offset: -2), session("c", offset: -3, kind: .strength), session("d", offset: -3, kind: .strength)]
        let ratings = ["a": SessionRating(rpe: 3, intensity: .moderate), "b": SessionRating(rpe: 6, intensity: .vigorous), "c": SessionRating(rpe: 4, intensity: .moderate, majorMuscleGroups: true), "d": SessionRating(rpe: 4, intensity: .moderate, majorMuscleGroups: true)]
        let r = Weekly.summarize(sessions, ratings: ratings, now: now, calendar: calendar)
        XCTAssertEqual(r.equivalentMinutes, 90); XCTAssertEqual(r.strengthDays, 1); XCTAssertEqual(r.recordedLoad, 510)
    }
    func testWorkoutsCannotDuplicateAndFutureNotCounted() {
        let s = session("one", offset: -1), duplicate = session("two", offset: -1)
        let result = Aggregation.nonOverlapping([s, duplicate])
        XCTAssertEqual(result.sessions.count, 1); XCTAssertEqual(result.omitted, 1)
        let future = session("future", offset: 1)
        XCTAssertEqual(Weekly.summarize([future], ratings: ["future": SessionRating(rpe: 5, intensity: .moderate)], now: now, calendar: calendar).totalSessions, 0)
    }
    func testDailySamplesDoNotInflateBaselineCoverage() {
        let sameDay = (1...30).map { DayValue(date: day(-10).addingTimeInterval(Double($0) * 60), value: Double($0)) }
        XCTAssertEqual(TrainingEngine.signal(sameDay, lower: true, logTransform: true, now: now, calendar: calendar).baselineDays, 1)
        XCTAssertEqual(Aggregation.dailyMedian(sameDay, calendar: calendar).first!.value, 15.5)
    }
    private func session(_ id: String, offset: Int, kind: SessionKind = .aerobic) -> Session {
        let start = day(offset).addingTimeInterval(8 * 3600)
        return Session(id: id, start: start, end: start.addingTimeInterval(1800), minutes: 30, kind: kind, title: "测试", source: "fixture")
    }
}
