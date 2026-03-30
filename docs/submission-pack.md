# Submission Pack Note

This note explains how to extract submission-friendly reference material from this PoC.

It is not the final `assets/eip-####/` directory.
It is the bridge between:

1. a runnable PoC repository; and
2. a compact attachment set suitable for an ERC submission.

## 1. What Should Be Extracted

If this repository is used as the source for formal submission material, the minimum extraction set should be:

### Interfaces

- `src/interfaces/IRiskRegistry.sol`
- `src/interfaces/IProtocolResponder.sol`

Only extract the interface fragments that are still intended to mirror the draft.
If a PoC-only helper remains in an interface, document it explicitly rather than silently promoting it into Core.
In the current PoC, helper and execution extras are already split out into:

- `src/interfaces/IProtocolResponseExecutor.sol`
- `src/interfaces/IProtocolResponseHelper.sol`

### Example responder implementation

- `src/SafeVault4626.sol`

This is not meant to be copied into the ERC body.
It is useful as attachment material because it demonstrates:

- trusted-registry gating;
- replay protection;
- local recovery;
- `getSupportedActions()` vs `getActiveRestrictions()`;
- deposit restriction with exits still open.

### Example registry implementation

- `src/MockRiskRegistry.sol`
- `src/MockAdjudicator.sol`

These are useful as illustrative attachment material, but should be labeled as mock/demo components rather than normative requirements.

### Key tests

The most important tests to cite or adapt are:

- `test/RiskResponseFlow.t.sol`
- `test/RiskStateLens.t.sol`
- `test/RiskAwareConsumerLens.t.sol`
- `test/AggregatorRouting.t.sol`

These collectively prove the semantic split between:

- registry history;
- responder truth;
- consumer behavior;
- local recovery with replay protection.

## 2. What Should Not Be Promoted Into Core By Accident

The following are useful in the PoC but should not be silently elevated into the ERC core:

- `trustedRiskRegistry()` as the only trust model;
- `IProtocolResponseHelper` as a mandatory surface;
- `IProtocolResponseExecutor` as a mandatory surface;
- `RiskStateLens`;
- `RiskAwareConsumerLens`;
- `MockAggregatorRouter`;
- exact `resultHash` encoding;
- exact mock adjudicator ownership pattern;
- exact script workflow.

These belong in:

- attachment notes;
- reviewer documentation;
- PoC repo context.

They do not automatically belong in the ERC specification itself.

## 3. Suggested Attachment Structure

When the time comes to prepare `assets/eip-####/`, a compact structure should be enough:

1. `interfaces/`
   - minimal `IRiskRegistry`
   - minimal `IProtocolResponder`
   - optional async execution extension fragment if still retained
2. `examples/`
   - responder example
   - mock registry example
3. `tests/`
   - only the few tests that prove the key semantic claims
4. `README.md`
   - scenario
   - scope boundary
   - how to run the selected tests
   - which pieces are illustrative vs normative

Do not copy the entire repository into the attachment set.

## 4. Recommended Test Claims For Submission Material

The attachment-level test story should stay narrow.

Recommended claims:

1. `Submitted` does not activate responder restrictions.
2. `UnderReview` does not activate responder restrictions.
3. `Confirmed` can exist while responder still reports no active restriction.
4. responder restrictions become machine-consumable after asynchronous execution.
5. consumer behavior follows responder truth rather than raw registry status.
6. registry-side `Resolved` remains distinct from protocol-local recovery.
7. local recovery clears active restrictions without erasing historical risk context.
8. replaying the same report after local recovery does not reactivate protection.

That is already enough to support the draft's main semantic boundary.

## 5. Current Repository Files That Already Help Reviewers

The shortest useful reviewer set is now:

1. `README.md`
2. `docs/reviewer-demo.md`
3. `docs/spec-map.md`
4. this file: `docs/submission-pack.md`

Those four documents together explain:

- what the PoC demonstrates;
- how to run it;
- how it maps to the draft;
- how it should later be reduced into submission-safe attachments.

## 6. Before Building The Real Attachment Set

Before extracting final submission assets, do one more check:

1. verify the draft still matches the current interface boundary;
2. verify no PoC helper is being accidentally promoted into Core;
3. verify the selected tests still prove the exact claims referenced by the draft;
4. verify the attachment README uses submission-safe language rather than repo-internal phrasing.
