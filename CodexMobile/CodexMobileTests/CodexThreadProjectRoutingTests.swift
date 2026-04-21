// FILE: CodexThreadProjectRoutingTests.swift
// Purpose: Verifies same-thread project rebind behavior for managed worktree handoff flows.
// Layer: Unit Test
// Exports: CodexThreadProjectRoutingTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

@MainActor
final class CodexThreadProjectRoutingTests: XCTestCase {
    private static var retainedServices: [CodexService] = []

    func testMoveThreadToProjectPathKeepsRebindWhenResumeFailsOnlyBecauseRolloutIsMissing() async throws {
        let service = makeService()
        let originalThread = CodexThread(
            id: "thread-1",
            title: "Source",
            cwd: "/tmp/remodex-local"
        )
        service.upsertThread(originalThread)
        service.activeThreadId = "thread-1"
        service.resumedThreadIDs = ["thread-1"]

        var resumeRequests: [[String: JSONValue]] = []
        service.requestTransportOverride = { method, params in
            XCTAssertEqual(method, "thread/resume")
            resumeRequests.append(params?.objectValue ?? [:])
            throw CodexServiceError.rpcError(
                RPCError(code: -32600, message: "no rollout found for thread id thread-1")
            )
        }

        let movedThread = try await service.moveThreadToProjectPath(
            threadId: "thread-1",
            projectPath: "/tmp/remodex-worktree"
        )

        XCTAssertEqual(resumeRequests.count, 1)
        XCTAssertEqual(resumeRequests.first?["threadId"]?.stringValue, "thread-1")
        XCTAssertEqual(resumeRequests.first?["cwd"]?.stringValue, "/tmp/remodex-worktree")
        XCTAssertEqual(movedThread.gitWorkingDirectory, "/tmp/remodex-worktree")
        XCTAssertEqual(service.thread(for: "thread-1")?.gitWorkingDirectory, "/tmp/remodex-worktree")
        XCTAssertEqual(service.currentAuthoritativeProjectPath(for: "thread-1"), "/tmp/remodex-worktree")
        XCTAssertEqual(service.activeThreadId, "thread-1")
        XCTAssertFalse(service.resumedThreadIDs.contains("thread-1"))
    }

    func testRolloutMissingFallbackStillRejectsImmediateStaleServerProjectPath() async throws {
        let service = makeService()
        service.upsertThread(
            CodexThread(
                id: "thread-1",
                title: "Source",
                cwd: "/tmp/remodex-local"
            )
        )
        service.activeThreadId = "thread-1"

        service.requestTransportOverride = { method, _ in
            XCTAssertEqual(method, "thread/resume")
            throw CodexServiceError.rpcError(
                RPCError(code: -32600, message: "no rollout found for thread id thread-1")
            )
        }

        _ = try await service.moveThreadToProjectPath(
            threadId: "thread-1",
            projectPath: "/tmp/remodex-worktree"
        )

        service.upsertThread(
            CodexThread(
                id: "thread-1",
                title: "Source",
                cwd: "/tmp/remodex-local"
            ),
            treatAsServerState: true
        )

        XCTAssertEqual(service.thread(for: "thread-1")?.gitWorkingDirectory, "/tmp/remodex-worktree")
        XCTAssertEqual(service.currentAuthoritativeProjectPath(for: "thread-1"), "/tmp/remodex-worktree")

        service.upsertThread(
            CodexThread(
                id: "thread-1",
                title: "Source",
                cwd: "/tmp/remodex-worktree"
            ),
            treatAsServerState: true
        )

        XCTAssertEqual(service.thread(for: "thread-1")?.gitWorkingDirectory, "/tmp/remodex-worktree")
        XCTAssertNil(service.currentAuthoritativeProjectPath(for: "thread-1"))
    }

    func testServerStateCannotOverwriteAuthoritativeRebindUntilMatchingPathArrives() {
        let service = makeService()
        service.upsertThread(
            CodexThread(
                id: "thread-1",
                title: "Source",
                cwd: "/tmp/remodex-local"
            )
        )

        service.beginAuthoritativeProjectPathTransition(
            threadId: "thread-1",
            projectPath: "/tmp/remodex-worktree"
        )

        service.upsertThread(
            CodexThread(
                id: "thread-1",
                title: "Source",
                cwd: "/tmp/remodex-local"
            ),
            treatAsServerState: true
        )

        XCTAssertEqual(service.thread(for: "thread-1")?.gitWorkingDirectory, "/tmp/remodex-worktree")
        XCTAssertEqual(service.currentAuthoritativeProjectPath(for: "thread-1"), "/tmp/remodex-worktree")

        service.upsertThread(
            CodexThread(
                id: "thread-1",
                title: "Source",
                cwd: "/tmp/remodex-worktree"
            ),
            treatAsServerState: true
        )

        XCTAssertEqual(service.thread(for: "thread-1")?.gitWorkingDirectory, "/tmp/remodex-worktree")
        XCTAssertNil(service.currentAuthoritativeProjectPath(for: "thread-1"))
    }

    func testManagedWorktreeAssociationPersistsAcrossLocalHandoffs() async throws {
        let service = makeService()
        service.upsertThread(
            CodexThread(
                id: "thread-1",
                title: "Source",
                cwd: "/tmp/remodex-local"
            )
        )

        var resumeResponses: [String] = []
        service.requestTransportOverride = { method, params in
            XCTAssertEqual(method, "thread/resume")
            let cwd = params?.objectValue?["cwd"]?.stringValue ?? ""
            resumeResponses.append(cwd)
            return RPCMessage(
                id: .string(UUID().uuidString),
                result: .object([
                    "thread": .object([
                        "id": .string("thread-1"),
                        "cwd": .string(cwd),
                        "title": .string("Source"),
                    ]),
                ]),
                includeJSONRPC: false
            )
        }

        let worktreePath = "/Users/me/.codex/worktrees/a1b2/remodex"
        _ = try await service.moveThreadToProjectPath(threadId: "thread-1", projectPath: worktreePath)
        _ = try await service.moveThreadToProjectPath(threadId: "thread-1", projectPath: "/tmp/remodex-local")

        XCTAssertEqual(resumeResponses, [worktreePath, "/tmp/remodex-local"])
        XCTAssertEqual(service.associatedManagedWorktreePath(for: "thread-1"), worktreePath)
    }

    func testStartTurnRebindsExistingThreadBeforeResumeWhenInputContainsCdDirective() async throws {
        let service = makeService()
        let originalPath = "/Users/lipan"
        let switchedPath = "/Users/lipan/Desktop/lil-agents-clean-project"
        service.upsertThread(
            CodexThread(
                id: "thread-1",
                title: "Source",
                cwd: originalPath
            )
        )
        service.activeThreadId = "thread-1"

        var resumedPaths: [String] = []
        var startedTurnThreadID: String?
        service.requestTransportOverride = { method, params in
            switch method {
            case "thread/resume":
                let cwd = params?.objectValue?["cwd"]?.stringValue ?? ""
                resumedPaths.append(cwd)
                return RPCMessage(
                    id: .string(UUID().uuidString),
                    result: .object([
                        "thread": .object([
                            "id": .string("thread-1"),
                            "cwd": .string(cwd),
                            "title": .string("Source"),
                        ]),
                    ]),
                    includeJSONRPC: false
                )
            case "turn/start":
                startedTurnThreadID = params?.objectValue?["threadId"]?.stringValue
                return RPCMessage(
                    id: .string(UUID().uuidString),
                    result: .object([
                        "turn": .object([
                            "id": .string("turn-1"),
                            "status": .string("inProgress"),
                            "items": .array([]),
                            "error": .null,
                        ]),
                    ]),
                    includeJSONRPC: false
                )
            default:
                XCTFail("Unexpected method: \(method)")
                return RPCMessage(id: .string(UUID().uuidString), result: .object([:]), includeJSONRPC: false)
            }
        }

        try await service.startTurn(
            userInput: "cd /Users/lipan/Desktop/lil-agents-clean-project",
            threadId: "thread-1",
            shouldAppendUserMessage: false
        )

        XCTAssertEqual(resumedPaths, [switchedPath])
        XCTAssertEqual(startedTurnThreadID, "thread-1")
        XCTAssertEqual(service.thread(for: "thread-1")?.gitWorkingDirectory, switchedPath)
    }

    func testStartTurnCreatesThreadInSwitchedProjectWhenInputContainsChineseDirectoryDirective() async throws {
        let service = makeService()
        let switchedPath = "/Users/lipan/Desktop/lil-agents-clean-project"

        var startedThreadPaths: [String] = []
        var resumedPaths: [String] = []
        service.requestTransportOverride = { method, params in
            switch method {
            case "thread/start":
                let cwd = params?.objectValue?["cwd"]?.stringValue ?? ""
                startedThreadPaths.append(cwd)
                return RPCMessage(
                    id: .string(UUID().uuidString),
                    result: .object([
                        "thread": .object([
                            "id": .string("thread-2"),
                            "title": .string("Source"),
                            "cwd": .string(cwd),
                        ]),
                    ]),
                    includeJSONRPC: false
                )
            case "thread/resume":
                let cwd = params?.objectValue?["cwd"]?.stringValue ?? ""
                resumedPaths.append(cwd)
                return RPCMessage(
                    id: .string(UUID().uuidString),
                    result: .object([
                        "thread": .object([
                            "id": .string("thread-2"),
                            "cwd": .string(cwd),
                            "title": .string("Source"),
                        ]),
                    ]),
                    includeJSONRPC: false
                )
            case "turn/start":
                return RPCMessage(
                    id: .string(UUID().uuidString),
                    result: .object([
                        "turn": .object([
                            "id": .string("turn-2"),
                            "status": .string("inProgress"),
                            "items": .array([]),
                            "error": .null,
                        ]),
                    ]),
                    includeJSONRPC: false
                )
            default:
                XCTFail("Unexpected method: \(method)")
                return RPCMessage(id: .string(UUID().uuidString), result: .object([:]), includeJSONRPC: false)
            }
        }

        try await service.startTurn(
            userInput: "进入 /Users/lipan/Desktop/lil-agents-clean-project 目录",
            threadId: nil,
            shouldAppendUserMessage: false
        )

        XCTAssertEqual(startedThreadPaths, [switchedPath])
        XCTAssertEqual(resumedPaths, [switchedPath])
        XCTAssertEqual(service.activeThreadId, "thread-2")
        XCTAssertEqual(service.thread(for: "thread-2")?.gitWorkingDirectory, switchedPath)
    }

    private func makeService(defaults: UserDefaults? = nil) -> CodexService {
        let resolvedDefaults: UserDefaults
        if let defaults {
            resolvedDefaults = defaults
        } else {
            let suiteName = "CodexThreadProjectRoutingTests.\(UUID().uuidString)"
            let isolatedDefaults = UserDefaults(suiteName: suiteName) ?? .standard
            isolatedDefaults.removePersistentDomain(forName: suiteName)
            resolvedDefaults = isolatedDefaults
        }

        let service = CodexService(defaults: resolvedDefaults)
        Self.retainedServices.append(service)
        return service
    }
}
