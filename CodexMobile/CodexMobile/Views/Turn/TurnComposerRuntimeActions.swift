// FILE: TurnComposerRuntimeActions.swift
// Purpose: Centralizes the composer runtime selection callbacks shared across nested views.
// Layer: View Helper
// Exports: TurnComposerRuntimeActions
// Depends on: CodexService, CodexServiceTier

import Foundation

struct TurnComposerRuntimeActions {
    let selectModel: (String) -> Void
    let selectAutomaticReasoning: () -> Void
    let selectReasoning: (String) -> Void
    let selectServiceTier: (CodexServiceTier?) -> Void

    @MainActor
    static func resolve(codex: CodexService) -> TurnComposerRuntimeActions {
        TurnComposerRuntimeActions(
            selectModel: { modelId in
                Task { @MainActor in
                    codex.setSelectedModelId(modelId)
                }
            },
            selectAutomaticReasoning: {
                Task { @MainActor in
                    codex.setSelectedReasoningEffort(nil)
                }
            },
            selectReasoning: { effort in
                Task { @MainActor in
                    codex.setSelectedReasoningEffort(effort)
                }
            },
            selectServiceTier: { serviceTier in
                Task { @MainActor in
                    codex.setSelectedServiceTier(serviceTier)
                }
            }
        )
    }
}
