//
//  BusinessDayTests.swift
//  BackdoorTests
//
//  Covers BusinessDay.currentBusinessDayISO, focused on the Case 1b
//  early-close grace-window fix. See BusinessDay.swift for the full
//  semantics of each case.
//

import Testing
import Foundation
@testable import Backdoor

@MainActor
struct BusinessDayTests {

    // MARK: - Fixtures

    private static let tokyo = "Asia/Tokyo"

    /// Make a Date at a specific wall-clock moment in the venue timezone.
    private func date(_ y: Int, _ mo: Int, _ d: Int,
                      _ h: Int, _ mi: Int = 0,
                      tz: String = BusinessDayTests.tokyo) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d
        c.hour = h; c.minute = mi
        return cal.date(from: c)!
    }

    private func settings(prep: Int16 = 240, grace: Int16 = 120,
                          tz: String = BusinessDayTests.tokyo) -> VenueSettings {
        VenueSettings(id: 1,
                      timezone: tz,
                      prepBufferMinutes: prep,
                      gracePeriodMinutes: grace,
                      updatedAt: nil)
    }

    /// Every weekday open 17:00–00:00 (midnight wrap) by default. Caller
    /// passes overrides for the weekdays that matter in each test.
    private func weekSchedule(_ overrides: [VenueDay]) -> [VenueDay] {
        var days = (Int16(1)...Int16(7)).map {
            VenueDay(weekday: $0, isClosed: false,
                     openTime: "17:00:00", closeTime: "00:00:00",
                     updatedAt: nil)
        }
        for o in overrides {
            if let i = days.firstIndex(where: { $0.weekday == o.weekday }) {
                days[i] = o
            }
        }
        return days
    }

    // MARK: - Case 1a: midnight-crossing shift, still inside close+grace

    @Test func case1a_midnightCrossing_withinGrace_returnsYesterday() {
        // Wed open 17:00, close 03:00 next day. Grace 60.
        // At 03:30 Thu we are past close but within grace.
        let wed = VenueDay(weekday: 3, isClosed: false,
                           openTime: "17:00:00", closeTime: "03:00:00",
                           updatedAt: nil)
        let sched = weekSchedule([wed])
        let sett = settings(grace: 60)
        // 2026-04-23 is Thursday. Yesterday = Wed = 2026-04-22.
        let now = date(2026, 4, 23, 3, 30)
        let iso = BusinessDay.currentBusinessDayISO(
            now: now, schedule: sched, settings: sett)
        #expect(iso == "2026-04-22")
    }

    // MARK: - Case 1b: the fix
    // The scenario where old and new code diverge: yesterday's early-close
    // shift has ENDED past its grace window, and today's prep window has
    // already begun. Old code: Case 1b short-circuits and returns yesterday
    // because nowClock < grace. New code: Case 1b correctly rejects
    // ((nowClock+1440) < (close+grace)), Case 2 fires and returns today.

    @Test func case1b_earlyClose_pastGrace_todayPrepStarted_returnsToday() {
        // Wed open 10:00, close 22:00 (no midnight cross). Grace 120 →
        // true end of Wed business day = 24:00 (midnight Thu start).
        // Thu opens 02:00, prep 60 → prep window starts at 01:00 Thu.
        // Grace = 120.
        //
        // At 01:30 Thu (nowClock = 90):
        //   - nowClock < grace(120) → old Case 1b fires → yesterday (WRONG)
        //   - (90 + 1440) = 1530  vs  (1320 + 120) = 1440 → 1530 < 1440
        //     is FALSE → new Case 1b correctly skips
        //   - Today's prep started at 01:00 (60 min into day, nowClock=90
        //     >= 60) → Case 2 fires → today (CORRECT)
        let wed = VenueDay(weekday: 3, isClosed: false,
                           openTime: "10:00:00", closeTime: "22:00:00",
                           updatedAt: nil)
        let thu = VenueDay(weekday: 4, isClosed: false,
                           openTime: "02:00:00", closeTime: "10:00:00",
                           updatedAt: nil)
        let sched = weekSchedule([wed, thu])
        let sett = settings(prep: 60, grace: 120)
        let now = date(2026, 4, 23, 1, 30)
        let iso = BusinessDay.currentBusinessDayISO(
            now: now, schedule: sched, settings: sett)
        #expect(iso == "2026-04-23")
    }

    @Test func case1b_earlyClose_withinGrace_returnsYesterday() {
        // Wed open 12:00, close 18:00 (early close, no midnight cross).
        // Grace 420 → true end = 01:00 Thu (extended, e.g. private event).
        // Thu opens 17:00, prep 240 → prep starts 13:00 Thu.
        //
        // At 00:30 Thu (nowClock = 30):
        //   - (30 + 1440) = 1470  vs  (1080 + 420) = 1500 → 1470 < 1500
        //     is TRUE → Case 1b fires → yesterday (CORRECT)
        let wed = VenueDay(weekday: 3, isClosed: false,
                           openTime: "12:00:00", closeTime: "18:00:00",
                           updatedAt: nil)
        let sched = weekSchedule([wed])
        let sett = settings(prep: 240, grace: 420)
        let now = date(2026, 4, 23, 0, 30)
        let iso = BusinessDay.currentBusinessDayISO(
            now: now, schedule: sched, settings: sett)
        #expect(iso == "2026-04-22")
    }

    // MARK: - Case 2: prep window has started on today's open day

    @Test func case2_prepWindowActive_returnsToday() {
        // Default schedule: every day 17:00–00:00. Prep 240 → prep starts
        // 13:00. At 14:00 Thu we are in the prep window.
        let sched = weekSchedule([])
        let sett = settings(prep: 240, grace: 120)
        let now = date(2026, 4, 23, 14, 0)
        let iso = BusinessDay.currentBusinessDayISO(
            now: now, schedule: sched, settings: sett)
        #expect(iso == "2026-04-23")
    }

    // MARK: - Case 3: walk back to most recent open day

    @Test func case3_betweenShifts_walksBackToMostRecentOpen() {
        // Make Thursday (today) closed. Grace & prep do not apply.
        // Yesterday (Wed) is open. Expect Wed.
        let thu = VenueDay(weekday: 4, isClosed: true,
                           openTime: nil, closeTime: nil, updatedAt: nil)
        let sched = weekSchedule([thu])
        let sett = settings(prep: 240, grace: 120)
        let now = date(2026, 4, 23, 10, 0)
        let iso = BusinessDay.currentBusinessDayISO(
            now: now, schedule: sched, settings: sett)
        #expect(iso == "2026-04-22")
    }

    @Test func case3_walksBackThroughClosedDays() {
        // Today (Thu) closed, yesterday (Wed) closed. Day before (Tue) open.
        // Expect Tue.
        let tue = VenueDay(weekday: 2, isClosed: false,
                           openTime: "17:00:00", closeTime: "00:00:00",
                           updatedAt: nil)
        let wed = VenueDay(weekday: 3, isClosed: true,
                           openTime: nil, closeTime: nil, updatedAt: nil)
        let thu = VenueDay(weekday: 4, isClosed: true,
                           openTime: nil, closeTime: nil, updatedAt: nil)
        let sched = weekSchedule([tue, wed, thu])
        let sett = settings(prep: 240, grace: 120)
        let now = date(2026, 4, 23, 10, 0)
        let iso = BusinessDay.currentBusinessDayISO(
            now: now, schedule: sched, settings: sett)
        #expect(iso == "2026-04-21")
    }

    // MARK: - isCurrentlyOpen

    @Test func isCurrentlyOpen_midnightCrossingShift() {
        // Wed 17:00 – 03:00 next day. At 02:00 Thu inside shift.
        let wed = VenueDay(weekday: 3, isClosed: false,
                           openTime: "17:00:00", closeTime: "03:00:00",
                           updatedAt: nil)
        let sched = weekSchedule([wed])
        let sett = settings()
        let now = date(2026, 4, 23, 2, 0)
        #expect(BusinessDay.isCurrentlyOpen(now: now, schedule: sched, settings: sett))
    }

    @Test func isCurrentlyOpen_outsideShift() {
        // Default schedule: 17:00 – 00:00 every day. At 15:00 Thu we are
        // before open (closed).
        let sched = weekSchedule([])
        let sett = settings()
        let now = date(2026, 4, 23, 15, 0)
        #expect(!BusinessDay.isCurrentlyOpen(now: now, schedule: sched, settings: sett))
    }

    @Test func isCurrentlyOpen_closedDayIsClosed() {
        // Thursday closed. At 20:00 (would be peak hours) still closed.
        let thu = VenueDay(weekday: 4, isClosed: true,
                           openTime: nil, closeTime: nil, updatedAt: nil)
        let sched = weekSchedule([thu])
        let sett = settings()
        let now = date(2026, 4, 23, 20, 0)
        #expect(!BusinessDay.isCurrentlyOpen(now: now, schedule: sched, settings: sett))
    }

    // MARK: - The Backdoor's actual live schedule

    @Test func backdoorLiveSchedule_wednesdayClosed_tuesdayAlsoClosed_returnsMonday() {
        // Live as of 2026-04: Mon/Thu/Fri/Sat/Sun 17:00-00:00, Tue+Wed closed.
        // On a Wed at 10:00 we're "between shifts" — walk back: Tue closed,
        // Mon open → return Monday.
        let sched: [VenueDay] = [
            .init(weekday: 1, isClosed: false, openTime: "17:00:00", closeTime: "00:00:00", updatedAt: nil),
            .init(weekday: 2, isClosed: true,  openTime: "17:00:00", closeTime: "03:00:00", updatedAt: nil),
            .init(weekday: 3, isClosed: true,  openTime: "17:00:00", closeTime: "03:00:00", updatedAt: nil),
            .init(weekday: 4, isClosed: false, openTime: "17:00:00", closeTime: "00:00:00", updatedAt: nil),
            .init(weekday: 5, isClosed: false, openTime: "17:00:00", closeTime: "00:00:00", updatedAt: nil),
            .init(weekday: 6, isClosed: false, openTime: "17:00:00", closeTime: "00:00:00", updatedAt: nil),
            .init(weekday: 7, isClosed: false, openTime: "17:00:00", closeTime: "00:00:00", updatedAt: nil),
        ]
        let sett = settings(prep: 510, grace: 120)
        // 2026-04-22 is a Wednesday (isodow 3).
        let now = date(2026, 4, 22, 10, 0)
        let iso = BusinessDay.currentBusinessDayISO(
            now: now, schedule: sched, settings: sett)
        #expect(iso == "2026-04-20") // Monday
    }
}
