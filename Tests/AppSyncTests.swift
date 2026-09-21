import XCTest
import HealthKit

@MainActor
private final class FakeHealth: HealthDataProviding {
    var failAuthorization = false
    var batches: [HealthSnapshot] = []
    var calls = 0
    var delay = false
    var changed: (() -> Void)?
    func authorize() async throws {
        if failAuthorization { throw NSError(domain: "test", code: 1) }
    }
    func observeChanges(_ action: @escaping () -> Void) { changed = action }
    func load(preferences: [String: String], onProgress: @escaping (HealthSnapshot) -> Void) async -> HealthSnapshot {
        let index = calls; calls += 1
        if delay { try? await Task.sleep(for: .milliseconds(80)) }
        let result = batches[min(index, batches.count - 1)]
        onProgress(result)
        return result
    }
}
@MainActor
final class AppSyncTests: XCTestCase {
    private func batch(_ steps: Double, sleep: Double = 8) -> HealthSnapshot {
        var value = HealthSnapshot()
        let today = Calendar.current.startOfDay(for: Date())
        value.metrics["steps"] = [DayValue(date: today, value: steps)]
        value.sleep = [DayValue(date: today, value: sleep)]
        value.completedQueries = HealthSnapshot.queryCount
        return value
    }
    private func model(_ health: FakeHealth) -> AppModel {
        let model = AppModel(health: health)
        model.adultAcknowledged = true; model.healthSheetCompleted = true
        return model
    }
    func testRefreshReplacesOldValuesAndRecomputesAdvice() async {
        let health = FakeHealth(); health.batches = [batch(100, sleep: 8), batch(900, sleep: 5)]
        let model = model(health)
        model.notes.checkIn = CheckIn(fatigue: 3)
        await model.refresh()
        XCTAssertEqual(model.snapshot.points(.steps).last?.value, 100)
        XCTAssertEqual(model.advice.level, .insufficient)
        await model.refresh()
        XCTAssertEqual(model.snapshot.points(.steps).last?.value, 900)
        XCTAssertEqual(model.advice.level, .ease)
        XCTAssertFalse(model.busy)
        XCTAssertTrue(model.syncStatus.contains("已更新"))
    }
    func testAuthorizationFailureDoesNotLeaveDemoOrOldReadings() async {
        let health = FakeHealth(); health.failAuthorization = true
        let model = model(health); model.showDemo()
        XCTAssertTrue(model.snapshot.hasAnyData)
        await model.connect()
        XCTAssertFalse(model.demo)
        XCTAssertFalse(model.snapshot.hasAnyData)
        XCTAssertNotNil(model.message)
        XCTAssertFalse(model.busy)
    }
    func testRefreshWhileBusyIsCoalescedAndExecuted() async {
        let health = FakeHealth(); health.delay = true; health.batches = [batch(100), batch(700)]
        let model = model(health)
        let first = Task { await model.refresh() }
        while health.calls == 0 { await Task.yield() }
        await model.refresh()
        await model.refresh()
        await first.value
        XCTAssertEqual(health.calls, 2)
        XCTAssertEqual(model.snapshot.points(.steps).last?.value, 700)
        XCTAssertFalse(model.busy)
    }
    func testObservedHealthChangeRefreshesData() async {
        let health = FakeHealth(); health.batches = [batch(10), batch(20)]
        let model = model(health)
        await model.refresh()
        health.changed?()
        try? await Task.sleep(for: .seconds(1))
        XCTAssertEqual(model.snapshot.points(.steps).last?.value, 20)
    }
    func testFailedCoreQueryDoesNotDiscardOtherMetrics() async {
        let service = HealthService()
        service.sampleReader = { type, _, _ in
            if type.identifier == HKQuantityTypeIdentifier.restingHeartRate.rawValue { throw NSError(domain: "test", code: 1) }
            return []
        }
        service.totalsReader = { metric, _, end, calendar in
            metric == .steps ? [DayValue(date: calendar.startOfDay(for: end), value: 2345)] : []
        }
        var updates = 0
        let result = await service.load(preferences: [:]) { _ in updates += 1 }
        XCTAssertEqual(result.points(.steps).last?.value, 2345)
        XCTAssertEqual(result.readWarnings.count, 1)
        XCTAssertEqual(result.completedQueries, HealthSnapshot.queryCount)
        XCTAssertEqual(updates, HealthSnapshot.queryCount)
        XCTAssertTrue(result.hasAnyData)
    }
    func testQueryTimeoutAndLateCallbackResumeOnlyOnce() async {
        var ticket: HealthQueryTicket<Int>?
        var stopped = 0
        do {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                let pending = HealthQueryTicket<Int>(continuation)
                ticket = pending
                pending.stop = { stopped += 1 }
                pending.startTimeout(seconds: 0.01)
            }
            XCTFail("Expected a timeout")
        } catch { XCTAssertEqual((error as NSError).code, 408) }
        ticket?.finish(.success(42))
        XCTAssertEqual(stopped, 1)
    }
    func testNoCheckInStillReflectsNewSleepData() async {
        let health = FakeHealth(); health.batches = [batch(100, sleep: 6)]
        let model = model(health); model.notes = PrivateNotes()
        await model.refresh()
        XCTAssertEqual(model.advice.level, .checkIn)
        XCTAssertTrue(model.advice.title.contains("数据已更新"))
        XCTAssertTrue(model.advice.evidence.contains { $0.contains("6.0") })
    }
}
