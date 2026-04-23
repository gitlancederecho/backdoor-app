//
//  DeleteFlowTests.swift
//  BackdoorTests
//
//  Lock in the serialization contract and enum shape for the
//  admin "soft-delete template + log event" path. Behavioural tests
//  (the 5s undo window, AdminViewModel.deleteTask side effects) need
//  a live DB / mocked client and live outside unit tests.
//

import Testing
import Foundation
@testable import Backdoor

struct DeleteFlowTests {

    private func matchingEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    @Test func taskEventTypeIncludesDeleted() {
        // The DB check constraint was broadened to accept 'deleted';
        // guard that the Swift enum stays in sync so the compiler
        // won't swallow a future rename or deletion of the case.
        #expect(TaskEventType.allCases.contains(.deleted))
        #expect(TaskEventType.deleted.rawValue == "deleted")
    }

    @Test func newTaskEventEncodesDeletedWithSnakeCaseKeys() throws {
        let dailyTaskId = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let actor = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let templateId = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!

        let event = NewTaskEvent(
            dailyTaskId: dailyTaskId,
            actorId: actor,
            eventType: TaskEventType.deleted.rawValue,
            fromValue: templateId.uuidString,
            toValue: nil,
            note: nil,
            photoUrl: nil
        )

        let data = try matchingEncoder().encode(event)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // Column names PostgREST will land on.
        #expect(decoded["daily_task_id"] as? String == dailyTaskId.uuidString)
        #expect(decoded["actor_id"] as? String == actor.uuidString)
        #expect(decoded["event_type"] as? String == "deleted")
        #expect(decoded["from_value"] as? String == templateId.uuidString)

        // Nil Optionals are dropped from the payload (PostgREST treats
        // absent columns as default / null).
        #expect(decoded["to_value"] == nil)
        #expect(decoded["note"] == nil)
        #expect(decoded["photo_url"] == nil)
    }

    @Test func newTaskEventEncodesUndoneForRestoreFlow() throws {
        // undoDeleteTask logs an `undone` event with to_value = template
        // id. Covers the reverse path.
        let dailyTaskId = UUID()
        let actor = UUID()
        let templateId = UUID()

        let event = NewTaskEvent(
            dailyTaskId: dailyTaskId,
            actorId: actor,
            eventType: TaskEventType.undone.rawValue,
            fromValue: nil,
            toValue: templateId.uuidString,
            note: nil,
            photoUrl: nil
        )

        let data = try matchingEncoder().encode(event)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(decoded["event_type"] as? String == "undone")
        #expect(decoded["to_value"] as? String == templateId.uuidString)
        #expect(decoded["from_value"] == nil)
    }
}
