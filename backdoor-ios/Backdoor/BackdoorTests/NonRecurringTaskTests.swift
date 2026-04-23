//
//  NonRecurringTaskTests.swift
//  BackdoorTests
//
//  Covers the non-recurring-task materialization contract. The
//  generate_daily_tasks RPC ignores is_recurring=false templates, so the
//  app needs to write a daily_tasks row directly. These tests lock in
//  the JSON shape that write depends on.
//

import Testing
import Foundation
@testable import Backdoor

struct NonRecurringTaskTests {

    /// The Supabase client's real configuration (see Config/Supabase.swift).
    /// We replicate it here so the test asserts exactly the wire format
    /// that will leave the app.
    private func matchingEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    @Test func newDailyTaskEncodesWithSnakeCaseKeys() throws {
        let taskId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let assignee = UUID(uuidString: "66666666-7777-8888-9999-aaaaaaaaaaaa")!
        let sample = NewDailyTask(
            taskId: taskId,
            date: "2026-04-23",
            assignedTo: assignee,
            status: "pending",
            startTime: "18:00:00",
            endTime: "20:00:00"
        )

        let data = try matchingEncoder().encode(sample)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // Keys must be snake_case — PostgREST targets the column names
        // directly; a camelCase key would drop onto the wrong column or
        // fail the insert.
        // Swift's UUID.uuidString emits uppercase, and the Supabase
        // encoder passes UUIDs through as strings — so we compare using
        // .uuidString directly instead of hard-coded lowercase.
        #expect(decoded["task_id"] as? String == taskId.uuidString)
        #expect(decoded["date"] as? String == "2026-04-23")
        #expect(decoded["assigned_to"] as? String == assignee.uuidString)
        #expect(decoded["status"] as? String == "pending")
        #expect(decoded["start_time"] as? String == "18:00:00")
        #expect(decoded["end_time"] as? String == "20:00:00")

        // No stray camelCase left over.
        #expect(decoded["taskId"] == nil)
        #expect(decoded["assignedTo"] == nil)
        #expect(decoded["startTime"] == nil)
        #expect(decoded["endTime"] == nil)
    }

    @Test func newDailyTaskOmitsNilOptionalsFromPayload() throws {
        // Unassigned ad-hoc task with no time window — admin just wrote
        // a title and saved. Swift's default JSONEncoder *omits* nil
        // Optionals from the output entirely (it does not emit JSON null).
        // PostgREST treats missing columns as "use default / leave null",
        // which is what we want for daily_tasks since assigned_to,
        // start_time, end_time are all nullable.
        let sample = NewDailyTask(
            taskId: UUID(),
            date: "2026-04-23",
            assignedTo: nil,
            status: "pending",
            startTime: nil,
            endTime: nil
        )

        let data = try matchingEncoder().encode(sample)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // Nil Optionals do not appear in the payload at all.
        #expect(decoded["assigned_to"] == nil)
        #expect(decoded["start_time"] == nil)
        #expect(decoded["end_time"] == nil)

        // Required fields still present.
        #expect(decoded["task_id"] as? String != nil)
        #expect(decoded["date"] as? String == "2026-04-23")
        #expect(decoded["status"] as? String == "pending")
    }

    /// Sanity: NewTask itself still encodes the way the existing create
    /// path expects. Regression guard if anyone reorders / adds fields.
    @Test func newTaskNonRecurringEncodesCorrectly() throws {
        let creator = UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!
        let task = NewTask(
            title: "Replace broken glass pitcher",
            titleJa: "割れたピッチャーの交換",
            category: .other,
            assignedTo: nil,
            isRecurring: false,
            recurrenceType: nil,
            recurrenceDays: [],
            priority: .normal,
            createdBy: creator,
            startTime: nil,
            endTime: nil
        )

        let data = try matchingEncoder().encode(task)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(decoded["title"] as? String == "Replace broken glass pitcher")
        #expect(decoded["title_ja"] as? String == "割れたピッチャーの交換")
        #expect(decoded["is_recurring"] as? Bool == false)
        #expect(decoded["category"] as? String == "other")
        #expect(decoded["priority"] as? String == "normal")
        #expect(decoded["created_by"] as? String == creator.uuidString)
        // Nil Optionals are omitted (see comment above).
        #expect(decoded["recurrence_type"] == nil)
        #expect(decoded["assigned_to"] == nil)
        #expect(decoded["start_time"] == nil)
        #expect(decoded["end_time"] == nil)
    }
}
