//
//  LoginPlanEngineTests.swift
//  EVEOpsTests
//
//  Covers the Login Planner: folding timers into the fewest logins, logging in at the
//  last moment within tolerance, available hours (including ones that wrap midnight),
//  what's already idle, skip costs, which capacity kinds count, and the "reacting to every
//  timer" comparison. Pure inputs only — no network, no ESI.
//

import Foundation
import Testing
@testable import EVEOps

private let hour: TimeInterval = 3600
private let pilot = 90_000_001

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// Midnight UTC, Thursday 1 October 2026.
private let midnight = utc.date(from: DateComponents(year: 2026, month: 10, day: 1))!

private func item(_ hours: Double, _ kind: IdleCapacityKind = .manufacturing, pilot id: Int = pilot) -> LoginPlanItem {
    LoginPlanItem(characterID: id, kind: kind, date: midnight.addingTimeInterval(hours * hour))
}

private func plan(_ items: [LoginPlanItem], tolerance: Double = 4, start: Int = 0, end: Int = 0,
                  horizonDays: Double = 3, now: Date = midnight) -> LoginPlan {
    LoginPlanEngine.plan(items, settings: LoginPlanSettings(tolerance: tolerance * hour, horizon: horizonDays * 86400,
                                                            dayStartHour: start, dayEndHour: end),
                         now: now, calendar: utc)
}

private func hours(_ date: Date) -> Double { date.timeIntervalSince(midnight) / hour }

@Suite struct LoginPlanEngineTests {
    // MARK: - Folding

    @Test func timersWithinToleranceShareOneLoginAtTheLastMoment() {
        let p = plan([item(1), item(2), item(3)])
        #expect(p.sessions.count == 1)
        // The first timer's window closes at 1h + 4h; the other two are due by then.
        #expect(hours(p.sessions[0].date) == 5)
        #expect(p.sessions[0].items.count == 3)
        #expect(p.reactiveLogins == 3)
    }

    @Test func farApartTimersNeedSeparateLogins() {
        let p = plan([item(1), item(10)], tolerance: 2)
        #expect(p.sessions.map { hours($0.date) } == [3, 12])
    }

    @Test func greedyPlanBeatsReactingToEveryTimer() {
        // Eight timers an hour apart, 4h tolerance: logins at 5h (covers 1…5) and 10h (6…8).
        let p = plan((1...8).map { item(Double($0)) })
        #expect(p.sessions.count == 2)
        #expect(p.reactiveLogins == 8)
        #expect(p.itemCount == 8)
    }

    @Test func waitTimeIsHowLongEachItemSitsBeforeItsLogin() {
        let p = plan([item(1), item(3)])
        // Login at 5h: waits of 4h and 2h.
        #expect(p.totalWait == 6 * hour)
    }

    @Test func itemsBeyondTheHorizonAreLeftOut() {
        let p = plan([item(1), item(30)], horizonDays: 1)
        #expect(p.itemCount == 1)
    }

    // MARK: - Availability

    @Test func offHoursTimerWaitsForTheFirstAvailableMoment() {
        // Due 01:00 with 2h tolerance — the whole window is before 08:00.
        let p = plan([item(1)], tolerance: 2, start: 8, end: 23)
        #expect(hours(p.sessions[0].date) == 8)
    }

    @Test func windowCrossingBedtimeLogsInAtTheEndOfTheDay() {
        // Due 21:00, 4h tolerance → deadline 01:00, but the day ends at 23:00.
        let p = plan([item(21)], tolerance: 4, start: 8, end: 23)
        #expect(hours(p.sessions[0].date) == 23)
    }

    @Test func availabilityCanWrapPastMidnight() {
        let availability = LoginPlanEngine.Availability(
            settings: LoginPlanSettings(dayStartHour: 18, dayEndHour: 2), calendar: utc
        )
        #expect(availability.contains(midnight.addingTimeInterval(1 * hour)))
        #expect(availability.contains(midnight.addingTimeInterval(20 * hour)))
        #expect(!availability.contains(midnight.addingTimeInterval(3 * hour)))
        #expect(!availability.contains(midnight.addingTimeInterval(12 * hour)))
    }

    @Test func equalHoursMeanAnyTime() {
        let availability = LoginPlanEngine.Availability(settings: LoginPlanSettings(dayStartHour: 5, dayEndHour: 5), calendar: utc)
        #expect(availability.contains(midnight.addingTimeInterval(3 * hour)))
    }

    @Test func loginsSnapToTheQuarterHour() {
        // Due 01:07 → window closes 05:07 → login at 05:00.
        let p = plan([item(1 + 7.0 / 60)])
        #expect(hours(p.sessions[0].date) == 5)
    }

    // MARK: - Already idle

    @Test func alreadyIdleItemsAreDueFromNow() {
        let now = midnight.addingTimeInterval(10 * hour)
        let p = plan([item(2)], now: now)
        #expect(hours(p.sessions[0].date) == 14)
        #expect(p.sessions[0].overdueCount(now: now) == 1)
        // Waiting is only counted from now.
        #expect(p.totalWait == 4 * hour)
    }

    // MARK: - Skip cost

    @Test func skippingALoginCostsItsItemsTheGapToTheNextOne() {
        let p = plan([item(1), item(2), item(20)], tolerance: 2)
        #expect(p.sessions.count == 2)
        // Login 1 at 3h with two items; login 2 at 22h → 2 × 19h.
        #expect(p.sessions[0].skipCost == 38 * hour)
        #expect(p.sessions[1].skipCost == nil)
    }

    @Test func sessionsListEachPilotOnceInDueOrder() {
        let other = 90_000_002
        let p = plan([item(2, pilot: other), item(1), item(3, pilot: other)])
        #expect(p.sessions[0].characterIDs == [pilot, other])
    }

    // MARK: - Items

    @Test func itemsTakeIdleLinesAndUpcomingEventsButNotFreeListingSlots() {
        let now = midnight
        let report = IdleCapacityReport(lines: [
            IdleCapacityLine(kind: .training, status: .idle),
            IdleCapacityLine(kind: .market, status: .idle, used: 2, limit: 10),
            IdleCapacityLine(kind: .manufacturing, status: .busy, used: 1, limit: 1),
        ])
        let events = [
            IdleCapacityEvent(kind: .manufacturing, date: now.addingTimeInterval(5 * hour)),
            IdleCapacityEvent(kind: .market, date: now.addingTimeInterval(6 * hour)),
            IdleCapacityEvent(kind: .cloneJump, date: now.addingTimeInterval(7 * hour)),
        ]
        let items = LoginPlanEngine.items(characterID: pilot, report: report, events: events, now: now)
        #expect(items.map(\.kind) == [.training, .manufacturing, .market])
        #expect(items[0].date == now)
    }

    @Test func excludedKindsAreLeftOut() {
        let report = IdleCapacityReport(lines: [IdleCapacityLine(kind: .training, status: .idle)])
        let events = [IdleCapacityEvent(kind: .extractors, date: midnight.addingTimeInterval(hour))]
        let items = LoginPlanEngine.items(characterID: pilot, report: report, events: events,
                                          kinds: [.extractors], now: midnight)
        #expect(items.map(\.kind) == [.extractors])
    }

    @Test func reactiveLoginsClusterTimersMinutesApart() {
        let items = [item(1), item(1 + 10.0 / 60), item(3)]
        #expect(LoginPlanEngine.reactiveLogins(items, now: midnight, until: midnight.addingTimeInterval(86400)) == 2)
    }
}
