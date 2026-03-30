# Risk Signaling and Response Interface

Status: Draft  
Type: Standards Track: ERC  
Created: 2026-03-30  
Requires: ERC-165

## Abstract

This ERC defines a minimal interface layer for machine-readable risk signaling, confirmation, and protocol response discovery.

The standard covers three things:

1. how a risk report enters a readable on-chain state machine;
2. how confirmation results are exposed with minimal adjudication metadata;
3. how a protocol exposes its currently active restrictions and its declared emergency response capabilities.

This ERC does not standardize risk detection logic, governance processes, forced withdrawals, execution incentives, or specific deleveraging algorithms. It does not grant registries, reporters, or executors direct control over protocol funds.

## Motivation

Most DeFi protocols already have their own pause, freeze, shutdown, guardian, and internal incident-response procedures. The missing layer is not another brake pedal, but a common machine-consumable interface for answering:

1. what risk was reported;
2. what confirmation result was produced;
3. what restrictions is the protocol currently exposing to external systems;
4. what low-intrusion protective actions does the protocol declare support for.

Without a common interface, wallets, aggregators, insurance systems, and risk dashboards must rely on protocol-specific integrations, private runbooks, or governance announcements. This makes risk handling fragmented and hard to consume across protocols.

This ERC defines a narrow signaling bus plus response-discovery surface. It is deliberately not a pre-admission permission system, and it is not a post-enforcement execution-constraint standard by itself.

It is especially well-suited to persistent or externally observable risks such as depegs, oracle drift, or dependency incidents. It is less suited to private exploit details that lose value once revealed publicly.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119][1] and [RFC 8174][2].

### Terminology

- **Signal Producer**: an actor that submits a risk report.
- **Adjudicator**: an actor or mechanism authorized by a registry implementation to write confirmation results.
- **Registry**: a contract exposing risk reports, status transitions, and confirmation metadata.
- **Protocol Responder**: a contract exposing the protocol's currently active restrictions and declared response capabilities.
- **Executor**: an actor that consumes a confirmed report and triggers a protocol-local protective action under an asynchronous execution model.
- **Consumer**: a wallet, aggregator, insurer, dashboard, router, or other external system reading registry and responder data.

### Design goals

A compliant implementation of this ERC MUST preserve the following boundaries:

1. `Submitted` and `UnderReview` are observable states, but MUST NOT automatically place a protocol into a protected mode.
2. Consumers determining the protocol's current restriction surface MUST treat the protocol responder as the source of truth.
3. Registries describe what was reported and confirmed; responders describe what restrictions are currently active.
4. Registries, reporters, and executors MUST NOT receive direct control over protocol funds solely by implementing this ERC.
5. If confirmation and execution are separated asynchronously, the implementation MUST provide at least one machine-readable discovery surface for confirmed-but-not-yet-consumed reports.

### Risk objects and state model

Each signal MUST at minimum carry the following fields:

```solidity
struct Signal {
    address target;
    bytes32 targetType;
    bytes32 riskType;
    uint8 severity;
    Status status;
}
```

Field semantics:

1. `target` identifies the on-chain object affected by the signal.
2. `targetType` identifies the category of the target. Core V1 RECOMMENDS values equivalent to `protocol`, `vault`, `asset`, and `dependency`.
3. `riskType` identifies the reported risk category.
4. `severity` is a consumer-facing severity hint. It MAY participate in implementation-defined prioritization, but MUST NOT be assumed to be the only input to report replacement or escalation logic.
5. Implementations MAY associate a signal with an implementation-defined dependency hint. If exposed, Core V1 treats it as single-hop only. Recursive dependency traversal is out of scope.

The registry status machine MUST support the following statuses:

```solidity
enum Status {
    None,
    Submitted,
    UnderReview,
    Confirmed,
    Rejected,
    Expired,
    Resolved
}
```

Status semantics:

1. `Submitted` means a report was accepted into registry state.
2. `UnderReview` means the report is being evaluated.
3. `Confirmed` means the report has received a standardized confirmation result.
4. `Rejected` means the report did not pass confirmation.
5. `Expired` means the report is no longer actionable.
6. `Resolved` means the risk event has been closed at the registry layer.

Implementations MAY support protocol-local recovery in addition to registry-layer `Resolved`, but protocol-local recovery MUST be distinguishable from registry-layer resolution. Core V1 does not standardize an `Executed` registry status. If implementations expose execution history, they SHOULD do so through extension events or helper views while keeping responder state as the source of truth for current restrictions.

### Resolution metadata

`Confirmed` MUST NOT be an empty label. A registry implementation MUST expose the following resolution metadata for a confirmed report:

```solidity
struct ResolutionMetadata {
    address adjudicator;
    bytes32 resolutionHash;
}
```

Implementations MAY expose richer confirmation metadata such as mechanism identifiers, challenge windows, or finality tiers, but those fields are not part of the Core V1 minimum interoperable surface.

### Registry interface

A registry implementation complying with this ERC MUST expose an interface equivalent to:

```solidity
interface IRiskRegistry {
    enum Status {
        None,
        Submitted,
        UnderReview,
        Confirmed,
        Rejected,
        Expired,
        Resolved
    }

    struct Signal {
        address target;
        bytes32 targetType;
        bytes32 riskType;
        uint8 severity;
        Status status;
    }

    struct ResolutionMetadata {
        address adjudicator;
        bytes32 resolutionHash;
    }

    event SignalRaised(
        bytes32 indexed reportId,
        address indexed producer,
        address indexed target,
        bytes32 targetType,
        bytes32 riskType,
        uint8 severity
    );

    event SignalResolved(
        bytes32 indexed reportId,
        address indexed target,
        Status indexed status,
        address adjudicator,
        bytes32 resolutionHash
    );

    function raiseSignal(
        address target,
        bytes32 targetType,
        bytes32 riskType,
        uint8 severity,
        bytes calldata evidenceRef
    ) external payable returns (bytes32 reportId);

    function resolveSignal(
        bytes32 reportId,
        Status finalStatus,
        ResolutionMetadata calldata resolution
    ) external;

    function getSignal(bytes32 reportId) external view returns (Signal memory signal);

    function getResolution(bytes32 reportId)
        external
        view
        returns (ResolutionMetadata memory resolution);
}
```

Registry requirements:

1. `Submitted` and `UnderReview` MUST remain observable without being treated as completed protection states.
2. The implementation MUST provide at least one machine-readable discovery path for confirmed-but-not-yet-consumed reports. Indexed `SignalResolved` events with `target` are sufficient for off-chain discovery. Implementations MAY additionally expose target-scoped view functions.

### Protocol responder interface

A responder implementation complying with this ERC MUST implement [ERC-165][3] and expose an interface equivalent to:

```solidity
interface IProtocolResponder is IERC165 {
    function getSupportedActions()
        external
        view
        returns (bytes32[] memory actionIds);

    function getActiveRestrictions()
        external
        view
        returns (bytes32[] memory restrictionIds);
}
```

Responder requirements:

1. Consumers determining whether an action is currently restricted MUST use responder output rather than registry status alone.
2. `getActiveRestrictions()` MUST expose the currently active restrictions as a set, not a single boolean.
3. `getSupportedActions()` MUST expose the responder's declared protective action surface.
4. A responder MAY support read-only adoption without exposing any execution hook.
5. Responders MAY expose additional helper views such as `emergencyStatus()` or restriction provenance, but those helpers are not part of Core V1.

Core V1 RECOMMENDS canonical low-intrusion identifiers equivalent to:

1. `PAUSE_DEPOSIT`
2. `PAUSE_NEW_RISK`
3. `RESTRICT_OUTFLOW`

Additional protocol-specific identifiers MAY be used.

### Optional asynchronous execution extension

Implementations that support asynchronous consumption of confirmed reports MAY expose an execution hook and execution-history events equivalent to:

```solidity
interface IProtocolResponseExecutor is IERC165 {
    event EmergencyActionExecuted(
        bytes32 indexed reportId,
        address indexed registry,
        address indexed executor,
        bytes32 actionId,
        bytes32 restrictionId,
        bytes32 resultHash
    );

    function triggerEmergencyAction(address registry, bytes32 reportId) external;
}
```

If an implementation exposes such an execution extension:

1. The responder MUST re-check registry state locally before entering a protected mode.
2. The responder MUST reject reports whose `target` does not match the responder.
3. The responder MUST provide replay protection at the report or report-plus-action level if local recovery is supported.
4. The core standard does not require a unified executor incentive model.
5. Extension-level execution history does not modify the Core V1 registry status set.

### Consumer semantics

Consumer-facing semantics MUST follow the rules below:

1. `Submitted` MAY trigger observation or warning, but MUST NOT be interpreted as an active protocol restriction.
2. `UnderReview` MAY trigger observation or warning, but MUST NOT be interpreted as an active protocol restriction.
3. `Confirmed` indicates that a report has been confirmed, but does not by itself prove that a responder has already activated a restriction.
4. Consumers deciding whether to block a user action MUST rely on the responder's current restriction surface.

## Rationale

### Why split registry and responder

The registry and responder are intentionally separated because they answer different questions.

1. The registry explains what happened and what was confirmed.
2. The responder explains what the protocol is currently restricting.

Without this split, consumers tend to misread a confirmed report as an active lock, or an optional execution-history event as proof that the current restriction is still active. This is especially dangerous when a protocol supports local recovery.

### Why `Submitted` and `UnderReview` are non-triggering

`Submitted` and `UnderReview` are useful for monitoring and warning surfaces, but they are too weak to serve as automatic protection triggers. Treating them as execution triggers would make low-quality or adversarial reports capable of forcing on-chain restriction state before confirmation.

### Why dependency references are single-hop in V1

Dependency graphs are real, but recursive on-chain traversal creates gas, liveness, and denial-of-service problems. Core V1 therefore treats dependency linkage, when exposed, as a direct single-hop hint only. Multi-hop propagation is left to indexers, caches, or implementation-specific strategies.

### Why asynchronous execution is preferred

Adjudication and protocol response are separated to prevent a responder revert from rolling back the confirmation transaction itself. This keeps the registry usable as a neutral bus even when a downstream protocol hook is faulty, paused, or temporarily unavailable.

### Why low-intrusion actions are prioritized

Core V1 focuses on low-intrusion responses because they are easier to adopt across existing guardian and governance systems. Higher-destruction actions such as automatic deleveraging or forced asset rerouting are more contentious and are better treated as extensions.

### Why trust-anchor discovery is not in core V1

A responder may expose a trust anchor such as `riskRegistry()` or `policyHash()`, and accompanying prototype work already explores that direction. However, Core V1 does not require a full trust-policy surface because the minimal interoperable requirement is the responder's current restriction state, not a universal governance or trust-configuration model.

### Why execution history is not part of core V1

It is useful to distinguish `Confirmed but not yet activated` from `currently restricted`, and implementations may record execution facts to help external systems reconstruct that timeline. However, execution-history recording is not required for minimal interoperability. A protocol can remain compliant in read-only mode if it exposes current restrictions through the responder interface.

### Why resolution metadata is intentionally minimal

Different ecosystems will use different adjudication models. Core V1 therefore only requires a readable confirmer identity and a stable resolution commitment. Challenge windows, mechanism identifiers, and richer finality tiers remain valuable, but they are better treated as implementation-defined metadata or extensions until forum pressure tests settle them.

### Why taxonomy and evidence schemas are deferred

Cross-protocol consumers benefit from converging on common `riskType` dictionaries and structured evidence formats. However, Core V1 does not require a canonical taxonomy or evidence schema because prematurely freezing one would likely overfit the first wave of adopters. These are better treated as informative guidance or future extensions once integrators have pressure-tested real usage.

## Non-goals

Core V1 does not attempt to standardize:

1. risk detection logic itself;
2. complete keeper networks or executor incentive systems;
3. unified reward, slash, or reputation curves;
4. recursive multi-hop dependency propagation;
5. forced withdrawals or user-side emergency exit algorithms;
6. atomic `0-day` exploit response within a single block.

## Future Extensions

Future versions may standardize:

1. richer `riskType` dictionaries or informative appendices;
2. stronger trust-anchor discovery such as `riskRegistry()` or `policyHash()`;
3. more destructive response actions;
4. asynchronous redemption coordination with standards such as [ERC-7540][4] or [ERC-7887][5];
5. stronger automatic interoperability with post-enforcement systems such as ERC-8192-derived implementations;
6. structured evidence guidance or optional schemas for `evidenceRef`, including compatibility profiles for external arbitration or review systems.

## Backwards Compatibility

This ERC is additive. It does not modify ERC-20, ERC-4626, or existing guardian and governance mechanisms. Protocols can adopt the responder interface in read-only mode first and add asynchronous execution or settlement outputs later.

## Test Cases

An implementation should pass at least the following behavioral tests:

1. a `Submitted` signal does not activate responder restrictions;
2. an `UnderReview` signal does not activate responder restrictions;
3. a `Confirmed` signal can exist while the responder still reports no active restriction;
4. after responder activation, restrictions become observable and machine-consumable;
5. after local recovery, the responder can report no active restriction while registry history remains visible;
6. replaying the same report after local recovery does not reactivate the restriction;
7. a consumer that reads only registry state reaches a different result than a consumer that correctly prioritizes responder state.

## Reference Implementation

Risk Signaling requires a dedicated proof-of-concept asset set. Legacy local ERC-8192 samples are not the reference implementation for this ERC.

A minimal Risk Signaling PoC should demonstrate:

1. a risk signal entering registry state;
2. adjudicator confirmation;
3. asynchronous activation of `PAUSE_DEPOSIT`;
4. `ERC-4626`-style `maxDeposit == 0` after responder activation;
5. router behavior that skips a vault only after responder restrictions are active;
6. protocol-local recovery with replay protection.

When preparing submission-safe reference material, extract it from separate Risk Signaling PoC assets or a dedicated sibling workspace rather than from unrelated legacy samples.

## Security Considerations

### Information leakage and front-running

Public evidence can itself become an attack surface. Core V1 is therefore better suited to persistent, non-atomic, externally consumable risks than to private 0-day exploit handling. Implementations can commit evidence by hash and reveal it later.

### Adjudicator trust and latency

This ERC standardizes how confirmation results are exposed, but it does not standardize who the adjudicator should be or how adjudication should be governed. In practice, adoption may still be constrained by the difficulty of choosing a confirmation path that is both trusted and fast enough for incident response. Different consumers may also assign different confidence weights to different adjudicators.

### Dynamic bonds and manipulation

If a registry uses dynamic bond pricing, it should enforce a nonzero floor. Dynamic pricing based solely on instantly manipulable values such as spot TVL, spot prices, or shallow liquidity can be abused exactly when the target is most fragile.

### Squatting and low-cost blocking

If a registry permits only one active report for a `(target, riskType)` pair, a low-quality report can block better reports unless escalation or override paths exist. Severity alone is not a sufficient override rule. Economic uplift or an equivalent priority rule is needed.

If an implementation supports bond-backed override or replacement, it should avoid locking the displaced reporter's bond indefinitely. Immediate release or an equivalent withdrawable balance is safer than forcing honest reporters into a liquidity war.

### False triggering from weak states

Automatically converting `Submitted` or `UnderReview` into on-chain protection would let adversarial or noisy reports force protocol restrictions before confirmation. Core V1 therefore forbids these states from acting as automatic triggers.

### Replay after local recovery

If a protocol supports local recovery while registry state remains `Confirmed` or while implementation-defined execution history remains visible, the responder must defend against replay. Otherwise the same historical report can repeatedly re-lock the protocol.

### Event semantics and indexability

Because implementations may choose different escalation, override, or local-recovery paths, event semantics must remain indexable. Registries and responders should make it possible for external systems to reconstruct report progression, optional execution history, and recovery from logs without relying on private coordination.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).

[1]: https://www.rfc-editor.org/rfc/rfc2119 "RFC 2119: Key words for use in RFCs to Indicate Requirement Levels"
[2]: https://www.rfc-editor.org/rfc/rfc8174 "RFC 8174: Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words"
[3]: https://eips.ethereum.org/EIPS/eip-165 "ERC-165: Standard Interface Detection"
[4]: https://eips.ethereum.org/EIPS/eip-7540 "ERC-7540: Asynchronous ERC-4626 Tokenized Vaults"
[5]: https://eips.ethereum.org/EIPS/eip-7887 "ERC-7887: Cancelable Async Deposits and Redeems"
