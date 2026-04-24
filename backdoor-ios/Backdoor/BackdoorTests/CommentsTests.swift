//
//  CommentsTests.swift
//  BackdoorTests
//
//  Wire-format coverage for task_comments. Same pattern as the other
//  payload tests: assert the JSON keys PostgREST lands on.
//

import Testing
import Foundation
@testable import Backdoor

struct CommentsTests {

    private func matchingEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    @Test func newTaskCommentEncodesWithSnakeCaseKeys() throws {
        let dailyTaskId = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let author = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let row = NewTaskComment(
            dailyTaskId: dailyTaskId,
            authorId: author,
            body: "I'll take this one"
        )

        let data = try matchingEncoder().encode(row)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(decoded["daily_task_id"] as? String == dailyTaskId.uuidString)
        #expect(decoded["author_id"] as? String == author.uuidString)
        #expect(decoded["body"] as? String == "I'll take this one")

        // No stray camelCase left over.
        #expect(decoded["dailyTaskId"] == nil)
        #expect(decoded["authorId"] == nil)
    }
}
