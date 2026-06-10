// FILE: CodexService+ThreadHistoryPagination.swift
// Purpose: Owns paginated thread history fetch, cursor state, and older-message reveal helpers.
// Layer: Service extension
// Exports: CodexService thread history pagination APIs
// Depends on: CodexService transport, CodexMessage history merge helpers, JSONValue

import Foundation

struct ThreadTurnsHistoryPage {
    let turns: [JSONValue]
    let nextCursor: JSONValue
}

extension CodexService {
    private func fetchThreadTurnsHistoryPage(
        threadId: String,
        limit: Int,
        cursor: JSONValue?,
        timeoutNanoseconds: UInt64
    ) async throws -> ThreadTurnsHistoryPage {
        var params: RPCObject = [
            "threadId": .string(threadId),
            "limit": .integer(limit),
            "sortDirection": .string("desc"),
        ]
        if let cursor, cursorHasValue(cursor) {
            params["cursor"] = cursor
        }

        let response = try await sendRequest(
            method: "thread/turns/list",
            params: .object(params),
            timeoutNanoseconds: timeoutNanoseconds
        )

        guard let resultObject = response.result?.objectValue else {
            throw CodexServiceError.invalidResponse("thread/turns/list response missing payload")
        }
        let turns =
            resultObject["data"]?.arrayValue
            ?? resultObject["items"]?.arrayValue
            ?? resultObject["turns"]?.arrayValue
        guard let turns else {
            throw CodexServiceError.invalidResponse("thread/turns/list response missing data array")
        }

        return ThreadTurnsHistoryPage(
            turns: turns,
            nextCursor: threadTurnsListCursor(from: resultObject)
        )
    }

    func fetchInitialThreadTurnsHistoryPage(threadId: String) async throws -> ThreadTurnsHistoryPage {
        let page = try await fetchThreadTurnsHistoryPage(
            threadId: threadId,
            limit: ThreadHistoryHydrationPolicy.initialTurnPageSize,
            cursor: nil,
            timeoutNanoseconds: ThreadHistoryHydrationPolicy.initialPageSoftTimeoutNanoseconds
        )
        debugSyncLog("thread/turns/list initial thread=\(threadId) limit=\(ThreadHistoryHydrationPolicy.initialTurnPageSize) turns=\(page.turns.count) hasNextCursor=\(cursorHasValue(page.nextCursor))")
        return page
    }

    func fetchLegacyThreadHistoryObject(threadId: String) async throws -> RPCObject {
        let response = try await sendRequest(
            method: "thread/read",
            params: .object([
                "threadId": .string(threadId),
                "includeTurns": .bool(true),
            ]),
            timeoutNanoseconds: ThreadHistoryHydrationPolicy.requestTimeoutNanoseconds
        )

        guard let threadObject = response.result?.objectValue?["thread"]?.objectValue else {
            throw CodexServiceError.invalidResponse("thread/read response missing thread payload")
        }
        return threadObject
    }

    func loadOlderThreadHistoryPage(threadId: String) async {
        guard let cursor = olderThreadHistoryCursorByThreadID[threadId],
              cursorHasValue(cursor),
              !hasKnownLocalHistoryStart(threadId: threadId),
              !loadingOlderThreadHistoryIDs.contains(threadId) else {
            return
        }

        loadingOlderThreadHistoryIDs.insert(threadId)
        olderHistoryLoadErrorByThreadID.removeValue(forKey: threadId)
        refreshThreadTimelineState(for: threadId)
        defer {
            loadingOlderThreadHistoryIDs.remove(threadId)
            refreshThreadTimelineState(for: threadId)
        }

        do {
            var pageCursor = cursor
            var duplicatePagesSkipped = 0

            while true {
                let page = try await fetchThreadTurnsHistoryPage(
                    threadId: threadId,
                    limit: ThreadHistoryHydrationPolicy.olderTurnPageSize,
                    cursor: pageCursor,
                    timeoutNanoseconds: ThreadHistoryHydrationPolicy.requestTimeoutNanoseconds
                )
                guard !Task.isCancelled else {
                    return
                }

                let threadObject: RPCObject = [
                    "id": .string(threadId),
                    "turns": .array(chronologicalTurnsFromDescendingPage(page.turns)),
                ]
                let olderMessages = decodeMessagesFromThreadRead(threadId: threadId, threadObject: threadObject)
                registerSubagentThreads(from: olderMessages, parentThreadId: threadId)

                let olderTerminalStates = decodeTurnTerminalStatesFromThreadRead(threadObject)
                _ = mergeHistoryTurnTerminalStates(
                    threadId: threadId,
                    terminalStatesByTurnID: olderTerminalStates
                )

                guard !olderMessages.isEmpty else {
                    if cursorHasValue(page.nextCursor),
                       page.nextCursor != pageCursor,
                       duplicatePagesSkipped < ThreadHistoryHydrationPolicy.duplicateOlderPageSkipLimit {
                        updateOlderThreadHistoryCursor(threadId: threadId, cursor: page.nextCursor)
                        pageCursor = page.nextCursor
                        duplicatePagesSkipped += 1
                        continue
                    }

                    finishOlderPageWithoutNewRows(
                        threadId: threadId,
                        nextCursor: page.nextCursor,
                        currentCursor: pageCursor
                    )
                    refreshThreadTimelineState(for: threadId)
                    return
                }

                let existingMessages = messagesByThread[threadId] ?? []
                let orderedOlderMessages = olderHistoryMessagesFilteredAndOrderedBeforeExisting(
                    olderMessages,
                    existingMessages: existingMessages
                )

                if orderedOlderMessages.isEmpty {
                    if cursorHasValue(page.nextCursor),
                       page.nextCursor != pageCursor,
                       duplicatePagesSkipped < ThreadHistoryHydrationPolicy.duplicateOlderPageSkipLimit {
                        updateOlderThreadHistoryCursor(threadId: threadId, cursor: page.nextCursor)
                        pageCursor = page.nextCursor
                        duplicatePagesSkipped += 1
                        continue
                    }

                    finishOlderPageWithoutNewRows(
                        threadId: threadId,
                        nextCursor: page.nextCursor,
                        currentCursor: pageCursor
                    )
                    refreshThreadTimelineState(for: threadId)
                    return
                }

                let merged = try await mergeHistoryMessagesOffMainActor(
                    existing: existingMessages,
                    history: orderedOlderMessages,
                    activeThreadIDs: Set(activeTurnIdByThread.keys),
                    runningThreadIDs: runningThreadIDs,
                    preferRecentWindow: false
                )

                guard !Task.isCancelled else {
                    return
                }

                if merged == existingMessages {
                    if cursorHasValue(page.nextCursor),
                       page.nextCursor != pageCursor,
                       duplicatePagesSkipped < ThreadHistoryHydrationPolicy.duplicateOlderPageSkipLimit {
                        updateOlderThreadHistoryCursor(threadId: threadId, cursor: page.nextCursor)
                        pageCursor = page.nextCursor
                        duplicatePagesSkipped += 1
                        continue
                    }

                    finishOlderPageWithoutNewRows(
                        threadId: threadId,
                        nextCursor: page.nextCursor,
                        currentCursor: pageCursor
                    )
                    refreshThreadTimelineState(for: threadId)
                    return
                }

                updateOlderCursorOrMarkStart(
                    threadId: threadId,
                    nextCursor: page.nextCursor,
                    currentCursor: pageCursor
                )
                expandThreadTimelineProjectionForRemoteOlderMessages(
                    threadId: threadId,
                    addedCount: orderedOlderMessages.count
                )
                messagesByThread[threadId] = merged
                persistMessages()
                updateCurrentOutput(for: threadId)
                return
            }
        } catch is CancellationError {
            return
        } catch {
            if consumeUnsupportedTurnPagination(error, attemptedMethod: "thread/turns/list") {
                return
            }
            noteThreadHistoryRemoteRevealFailed(threadId: threadId)
            olderHistoryLoadErrorByThreadID[threadId] = "Couldn't load earlier messages. Tap to retry."
            refreshThreadTimelineState(for: threadId)
            debugSyncLog("failed to load older history page for thread=\(threadId): \(error.localizedDescription)")
        }
    }

    func canLoadOlderThreadHistory(threadId: String) -> Bool {
        (hasRemoteOlderThreadHistoryCursor(threadId: threadId)
            && !hasKnownLocalHistoryStart(threadId: threadId))
            || hasLocallyProjectedEarlierThreadHistory(threadId: threadId)
    }

    func hasRemoteOlderThreadHistoryCursor(threadId: String) -> Bool {
        cursorHasValue(olderThreadHistoryCursorByThreadID[threadId])
    }

    func hasAuthoritativeLocalHistoryStart(threadId: String) -> Bool {
        threadsWithAuthoritativeLocalHistoryStart.contains(threadId)
    }

    func hasKnownLocalHistoryStart(threadId: String) -> Bool {
        hasAuthoritativeLocalHistoryStart(threadId: threadId)
    }

    func markThreadLocalHistoryStartAuthoritative(_ threadId: String, clearRemoteCursor: Bool = false) {
        threadsWithAuthoritativeLocalHistoryStart.insert(threadId)
        exhaustedOlderThreadHistoryCursorByThreadID.removeValue(forKey: threadId)
        if clearRemoteCursor {
            clearOlderThreadHistoryCursor(threadId: threadId, persistState: false)
        }
        persistThreadHistoryPaginationState()
    }

    func isLoadingOlderThreadHistory(threadId: String) -> Bool {
        loadingOlderThreadHistoryIDs.contains(threadId)
    }

    func hasSatisfiedInitialThreadHistoryLoad(threadId: String) -> Bool {
        !supportsTurnPagination || initialTurnsLoadedByThreadID.contains(threadId)
    }

    func hasLocallyProjectedEarlierThreadHistory(threadId: String) -> Bool {
        let currentLimit = threadTimelineProjectionLimitByThreadID[threadId]
            ?? TurnTimelineProjectionPolicy.initialMessageLimit
        return (messagesByThread[threadId]?.count ?? 0) > currentLimit
    }

    func noteThreadHistoryRevealRequested(threadId: String, pageSize: Int) {
        let normalizedPageSize = max(1, pageSize)
        let currentLimit = threadTimelineProjectionLimitByThreadID[threadId]
            ?? TurnTimelineProjectionPolicy.initialMessageLimit
        let nextLimit = currentLimit + normalizedPageSize
        let totalMessages = messagesByThread[threadId]?.count ?? 0
        guard totalMessages > currentLimit else {
            if totalMessages > 0,
               hasKnownLocalHistoryStart(threadId: threadId)
                || localCacheStartsAtThreadCreation(
                    threadId: threadId,
                    existingMessages: messagesByThread[threadId] ?? []
                ) {
                markThreadLocalHistoryStartAuthoritative(threadId, clearRemoteCursor: true)
            }
            refreshThreadTimelineState(for: threadId)
            return
        }
        threadTimelineProjectionLimitByThreadID[threadId] = nextLimit
        olderHistoryLoadErrorByThreadID.removeValue(forKey: threadId)
        if nextLimit >= totalMessages {
            if hasKnownLocalHistoryStart(threadId: threadId)
                || localCacheStartsAtThreadCreation(
                    threadId: threadId,
                    existingMessages: messagesByThread[threadId] ?? []
                ) {
                markThreadLocalHistoryStartAuthoritative(threadId, clearRemoteCursor: true)
            }
        }

        if totalMessages > currentLimit {
            noteMessagesChanged(for: threadId)
            refreshThreadTimelineState(for: threadId)
        }
    }

    func noteThreadHistoryRevealRequested(threadId: String) {
        noteThreadHistoryRevealRequested(
            threadId: threadId,
            pageSize: TurnTimelineProjectionPolicy.messagePageSize
        )
    }

    func noteThreadHistoryRemoteRevealFailed(threadId: String) {
        let loadedCount = messagesByThread[threadId]?.count ?? 0
        let currentLimit = threadTimelineProjectionLimitByThreadID[threadId]
            ?? TurnTimelineProjectionPolicy.initialMessageLimit
        guard currentLimit > loadedCount else {
            return
        }

        threadTimelineProjectionLimitByThreadID[threadId] = max(
            TurnTimelineProjectionPolicy.initialMessageLimit,
            loadedCount
        )
        noteMessagesChanged(for: threadId)
        refreshThreadTimelineState(for: threadId)
    }

    func clearDeferredThreadHistoryErrorIfNeeded(threadId: String) {
        olderHistoryLoadErrorByThreadID.removeValue(forKey: threadId)
        if activeThreadId == threadId,
           lastErrorMessage == "Couldn't load this chat yet. Retrying in the background." {
            lastErrorMessage = nil
        }
    }

    func updateThreadTimelineProjectionForEmbeddedHistory(threadId: String, decodedMessageCount: Int) {
        threadTimelineProjectionLimitByThreadID[threadId] = max(
            threadTimelineProjectionLimitByThreadID[threadId] ?? 0,
            TurnTimelineProjectionPolicy.initialMessageLimit
        )
    }

    func seedThreadTimelineProjectionForPaginatedHistory(threadId: String, decodedMessageCount: Int) {
        threadTimelineProjectionLimitByThreadID[threadId] = max(
            threadTimelineProjectionLimitByThreadID[threadId] ?? 0,
            TurnTimelineProjectionPolicy.initialMessageLimit,
            decodedMessageCount
        )
    }

    func markThreadPaginatedHistorySatisfied(_ threadId: String) {
        threadTimelineProjectionLimitByThreadID[threadId] = max(
            threadTimelineProjectionLimitByThreadID[threadId] ?? 0,
            TurnTimelineProjectionPolicy.initialMessageLimit
        )
    }

    func chronologicalTurnsFromDescendingPage(_ turns: [JSONValue]) -> [JSONValue] {
        Array(turns.reversed())
    }

    func updateOlderThreadHistoryCursorFromInitialPage(threadId: String, cursor: JSONValue, isFreshInitialLoad: Bool) {
        guard isFreshInitialLoad else {
            return
        }
        if hasAuthoritativeLocalHistoryStart(threadId: threadId) {
            clearOlderThreadHistoryCursor(threadId: threadId)
            return
        }
        if cursorHasValue(cursor) {
            if exhaustedOlderThreadHistoryCursorByThreadID[threadId] == cursor {
                clearOlderThreadHistoryCursor(threadId: threadId, clearExhaustedCursor: false)
                return
            }
            threadsWithAuthoritativeLocalHistoryStart.remove(threadId)
            updateOlderThreadHistoryCursor(threadId: threadId, cursor: cursor)
        } else {
            markThreadLocalHistoryStartAuthoritative(threadId, clearRemoteCursor: true)
        }
    }

    func persistThreadHistoryPaginationState() {
        let threadIDs = Set(olderThreadHistoryCursorByThreadID.keys)
            .union(threadsWithAuthoritativeLocalHistoryStart)
            .union(exhaustedOlderThreadHistoryCursorByThreadID.keys)
        let stateByThreadID = threadIDs.reduce(into: [String: CodexThreadHistoryPaginationState]()) { partial, threadId in
            let cursor = olderThreadHistoryCursorByThreadID[threadId]
            let exhaustedCursor = exhaustedOlderThreadHistoryCursorByThreadID[threadId]
            let hasCursor = cursorHasValue(cursor)
            let hasExhaustedCursor = cursorHasValue(exhaustedCursor)
            let hasAuthoritativeStart = threadsWithAuthoritativeLocalHistoryStart.contains(threadId)
            guard hasCursor || hasExhaustedCursor || hasAuthoritativeStart else {
                return
            }
            partial[threadId] = CodexThreadHistoryPaginationState(
                olderCursor: hasCursor ? cursor : nil,
                exhaustedOlderCursor: hasExhaustedCursor ? exhaustedCursor : nil,
                hasAuthoritativeLocalHistoryStart: hasAuthoritativeStart
            )
        }

        guard !stateByThreadID.isEmpty else {
            defaults.removeObject(forKey: Self.threadHistoryPaginationStateDefaultsKey)
            return
        }
        guard let data = try? encoder.encode(stateByThreadID) else {
            return
        }
        defaults.set(data, forKey: Self.threadHistoryPaginationStateDefaultsKey)
    }
}

private extension CodexService {
    func olderHistoryMessagesFilteredAndOrderedBeforeExisting(
        _ olderMessages: [CodexMessage],
        existingMessages: [CodexMessage]
    ) -> [CodexMessage] {
        let existingItemIDs = Set(existingMessages.compactMap { Self.normalizedHistoryIdentifier($0.itemId) })
        let existingMessageKeys = Set(existingMessages.map(Self.historyMessageKey(for:)))
        let filtered = olderMessages.filter { message in
            if let itemID = Self.normalizedHistoryIdentifier(message.itemId),
               existingItemIDs.contains(itemID) {
                return false
            }
            return !existingMessageKeys.contains(Self.historyMessageKey(for: message))
        }

        guard let firstExistingOrder = existingMessages.map(\.orderIndex).min() else {
            return filtered
        }

        var ordered = filtered
        let startOrder = firstExistingOrder - ordered.count
        for index in ordered.indices {
            ordered[index].orderIndex = startOrder + index
        }
        return ordered
    }

    func threadTurnsListCursor(from resultObject: RPCObject) -> JSONValue {
        if let nextCursor = resultObject["nextCursor"] {
            return nextCursor
        }
        if let nextCursor = resultObject["next_cursor"] {
            return nextCursor
        }
        return .null
    }

    func updateOlderThreadHistoryCursor(threadId: String, cursor: JSONValue) {
        if cursorHasValue(cursor) {
            exhaustedOlderThreadHistoryCursorByThreadID.removeValue(forKey: threadId)
            olderThreadHistoryCursorByThreadID[threadId] = cursor
            persistThreadHistoryPaginationState()
        } else {
            clearOlderThreadHistoryCursor(threadId: threadId)
        }
    }

    func updateOlderCursorOrMarkStart(threadId: String, nextCursor: JSONValue, currentCursor: JSONValue? = nil) {
        if cursorHasValue(nextCursor) {
            if let currentCursor, nextCursor == currentCursor {
                markOlderThreadHistoryCursorExhausted(threadId: threadId, cursor: currentCursor)
                return
            }
            updateOlderThreadHistoryCursor(threadId: threadId, cursor: nextCursor)
        } else {
            markThreadLocalHistoryStartAuthoritative(threadId, clearRemoteCursor: true)
        }
    }

    func finishOlderPageWithoutNewRows(threadId: String, nextCursor: JSONValue, currentCursor: JSONValue) {
        updateOlderCursorOrMarkStart(
            threadId: threadId,
            nextCursor: nextCursor,
            currentCursor: currentCursor
        )
    }

    func markOlderThreadHistoryCursorExhausted(threadId: String, cursor: JSONValue) {
        olderThreadHistoryCursorByThreadID.removeValue(forKey: threadId)
        olderHistoryLoadErrorByThreadID.removeValue(forKey: threadId)
        exhaustedOlderThreadHistoryCursorByThreadID[threadId] = cursor
        persistThreadHistoryPaginationState()
    }

    func clearOlderThreadHistoryCursor(
        threadId: String,
        persistState: Bool = true,
        clearExhaustedCursor: Bool = true
    ) {
        olderThreadHistoryCursorByThreadID.removeValue(forKey: threadId)
        olderHistoryLoadErrorByThreadID.removeValue(forKey: threadId)
        if clearExhaustedCursor {
            exhaustedOlderThreadHistoryCursorByThreadID.removeValue(forKey: threadId)
        }
        if persistState {
            persistThreadHistoryPaginationState()
        }
    }

    func cursorHasValue(_ cursor: JSONValue?) -> Bool {
        guard let cursor else {
            return false
        }
        switch cursor {
        case .null:
            return false
        case .string(let value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private func shouldTrustExistingCacheAsPrePaginationFullHistory(
        threadId: String,
        existingMessages: [CodexMessage],
        paginatedMessages: [CodexMessage],
        hadInitialTurnsLoadedBeforeRefresh: Bool,
        hadAuthoritativeLocalStartBeforeRefresh: Bool
    ) -> Bool {
        guard !hadInitialTurnsLoadedBeforeRefresh,
              !hadAuthoritativeLocalStartBeforeRefresh,
              !paginatedMessages.isEmpty,
              existingMessages.count > paginatedMessages.count else {
            return false
        }

        let existingItemIDs = Set(existingMessages.compactMap { Self.normalizedHistoryIdentifier($0.itemId) })
        let existingKeys = Set(existingMessages.map(Self.historyMessageKey(for:)))
        let exactOverlapCount = paginatedMessages.reduce(into: 0) { count, message in
            if let itemID = Self.normalizedHistoryIdentifier(message.itemId),
               existingItemIDs.contains(itemID) {
                count += 1
                return
            }
            if existingKeys.contains(Self.historyMessageKey(for: message)) {
                count += 1
            }
        }
        let localStartsAtThreadCreation = localCacheStartsAtThreadCreation(
            threadId: threadId,
            existingMessages: existingMessages
        )
        let localHasSubstantialPrefix = existingMessages.count >= max(
            TurnTimelineProjectionPolicy.initialMessageLimit,
            paginatedMessages.count * 2
        )

        return localStartsAtThreadCreation
            && localHasSubstantialPrefix
            && exactOverlapCount > 0
    }

    func localCacheStartsAtThreadCreation(threadId: String, existingMessages: [CodexMessage]) -> Bool {
        guard let threadCreatedAt = thread(for: threadId)?.createdAt,
              let oldestMessageDate = existingMessages.map(\.createdAt).min() else {
            return false
        }

        return oldestMessageDate <= threadCreatedAt.addingTimeInterval(180)
    }

    func expandThreadTimelineProjectionForRemoteOlderMessages(threadId: String, addedCount: Int) {
        guard addedCount > 0 else {
            return
        }
        let currentLimit = threadTimelineProjectionLimitByThreadID[threadId]
            ?? TurnTimelineProjectionPolicy.initialMessageLimit
        threadTimelineProjectionLimitByThreadID[threadId] = currentLimit + addedCount
    }
}
