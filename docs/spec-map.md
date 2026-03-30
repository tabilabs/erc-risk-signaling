# Draft-to-PoC Mapping

This note explains how the current PoC maps to the latest `Risk Signaling and Response Interface` draft.

The point is not to claim that every PoC-only helper belongs in Core.
The point is to make the boundary explicit so reviewers can see:

1. which parts are intended to mirror the draft;
2. which parts are PoC instrumentation;
3. which draft topics are still intentionally left out.

## 1. Core Surfaces Reflected by This PoC

### `IRiskRegistry`

The PoC mirrors the current draft on the following points:

- core registry status excludes `Executed`;
- `Signal` includes `target`, `targetType`, `riskType`, `severity`, and `status`;
- `Submitted` and `UnderReview` remain observable states only;
- `Confirmed` carries separate `ResolutionMetadata`;
- execution history is not modeled as a core status transition.

PoC-specific additions:

- `dependencyRef`
- raw `evidence` bytes
- `bond`
- `producer`

These are useful for the demo, but they are not all required to be part of the minimum interoperable surface in a final ERC.

### `IProtocolResponder`

The PoC mirrors the current draft on the following points:

- responder is the machine-readable source of truth for current live restrictions;
- `getSupportedActions()` is exposed separately from `getActiveRestrictions()`;
- restrictions are modeled as a set, not a single boolean;
- emergency execution is asynchronous.

PoC-specific additions:

- `trustedRiskRegistry()`
- `emergencyStatus()`
- `resolveLocalEmergency(string reason)`

These exist to make the trust-anchor model and local recovery path directly inspectable.

### Execution History

The draft direction is:

- keep core registry status narrow;
- expose execution history through events or helper views.

The PoC follows that direction by using:

- `SignalExecutionRecorded`
- `EmergencyActionExecuted`
- `getExecution(reportId)`

This is deliberate. The PoC no longer treats execution as a core registry status.

## 2. Behaviors This PoC Explicitly Proves

The current test suite proves the following draft-aligned claims:

1. `Submitted` does not activate restrictions.
2. `UnderReview` does not activate restrictions.
3. `Confirmed` can exist while the responder still reports no active restriction.
4. responder state, not raw registry state, controls whether deposits should be blocked.
5. a trusted-registry model can exist without turning the registry into a governance control plane.
6. replaying an already consumed report does not reactivate local emergency mode after recovery.
7. a consumer can distinguish:
   - confirmed but not yet executed
   - active restriction
   - local recovery with retained history
   - execution/history mismatch

## 3. PoC Instrumentation That Is Not Core

These parts should be read as demo helpers, not as assertions about mandatory final-standard shape:

- `MockAdjudicator`
- `MockExecutor`
- `MockAggregatorRouter`
- `RiskStateLens`
- `RiskAwareConsumerLens`
- the exact `resultHash` encoding
- the exact `trustedRiskRegistry()` trust-anchor model

They are useful because they let reviewers observe the separation between registry history and responder truth without having to imagine how consumers would derive it.

## 4. Draft Topics Not Fully Covered Yet

The PoC is intentionally narrow. It does not yet try to fully cover:

1. registry-side `Resolved` as a separate closure path alongside local recovery;
2. a richer `targetType` taxonomy beyond the single vault-focused demo path;
3. structured evidence schemas;
4. replacement or escalation economics;
5. multiple action types beyond `PAUSE_DEPOSIT`;
6. submission-safe attachment packaging for `assets/eip-####/`.

These are still valid follow-on tasks, but they are not required for the current PoC to demonstrate the core semantic split.

## 5. Recommended Reviewer Reading Order

If you want the shortest path:

1. `README.md`
2. `docs/reviewer-demo.md`
3. `docs/spec-map.md`
4. `src/interfaces/IRiskRegistry.sol`
5. `src/interfaces/IProtocolResponder.sol`
6. `test/RiskResponseFlow.t.sol`

## 6. Why This Mapping Note Exists

Without this note, a reviewer can easily misread:

- a PoC helper as if it were Core; or
- a draft boundary as if it had already been implemented in every possible form.

This repository is trying to prove one narrow point:

- risk history;
- confirmation metadata;
- responder truth;
- asynchronous execution;
- local recovery;

can coexist without collapsing back into a single overloaded emergency status machine.
