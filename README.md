# Risk Signaling Response PoC

Minimal `Foundry` proof of concept for the proposed `Risk Signaling and Response Interface`.

This repository demonstrates a narrow, machine-readable incident flow:

1. a reporter raises a risk signal;
2. an adjudicator confirms the signal;
3. an executor triggers a protocol-local emergency action asynchronously;
4. an `ERC-4626` vault pauses new deposits and exposes `maxDeposit == 0`;
5. a consumer and router stop directing new flow into the restricted vault;
6. exit paths remain available;
7. local recovery clears the active restriction without erasing historical risk facts.

The repository is intentionally small. It does not attempt to standardize keeper incentives, detection models, forced withdrawals, or governance frameworks.

## What This PoC Tries to Prove

- `Submitted` and `UnderReview` are observable states, not automatic lock triggers.
- The protocol responder is the source of truth for current restrictions.
- Registry state and responder state remain distinct under asynchronous execution.
- Consumers can derive routing decisions without treating raw registry status as equivalent to live protocol restrictions.
- Local recovery does not allow historical reports to replay the vault back into emergency mode.
- A responder can require a trusted risk registry instead of accepting arbitrary confirmed reports from any registry.

## Repository Layout

- `src/interfaces/`
  - Minimal interface layer for the PoC.
- `src/`
  - Mock registry, adjudicator, executor, vault, router, and read-only consumer helpers.
- `script/`
  - Deployment, signal raising, execution, recovery, and read-only observation scripts.
- `test/`
  - Flow, routing, state-lens, consumer-lens, and script guard-rail tests.
- `docs/`
  - Reviewer-focused demo instructions.

## Quickstart

If you only want the shortest reviewer path, start with [docs/reviewer-demo.md](docs/reviewer-demo.md).

For local development:

```bash
forge build
forge test
```

The repository ignores `.env` and `.env.local` so local demo keys do not get committed.

## Core Components

### Registry Layer

- `MockRiskRegistry`
  - Stores signals and status transitions.
- `MockAdjudicator`
  - Confirms a signal by moving it into `Confirmed`.

This layer explains what was reported and what was confirmed.

### Responder Layer

- `SafeVault4626`
  - `ERC-4626` vault with protocol-local emergency controls.
  - Tracks processed reports for replay protection.
  - Requires a `trustedRiskRegistry` for emergency execution.

This layer explains what restrictions are actually active right now.

### Consumer Layer

- `RiskStateLens`
  - Aggregates registry state and responder state into one snapshot.
- `RiskAwareConsumerLens`
  - Converts that snapshot into consumer-facing decisions.
- `MockAggregatorRouter`
  - Consumes the decision output directly and reroutes around restricted vaults.

This layer demonstrates how external systems can stay decoupled from protocol-specific risk logic.

## Trusted Registry Model

The responder does not accept every confirmed report from every registry.

Instead:

1. the vault exposes `trustedRiskRegistry()`;
2. the executor must pass that exact registry address when triggering the emergency action;
3. a report confirmed by an untrusted registry remains observable, but it must not place the vault into emergency mode;
4. consumers should treat the trusted registry as the responder's execution trust anchor.

This matters because a registry is a signaling bus, not an automatic governance control plane.

## Demo Flow

The main demo path is:

1. `DeployRiskResponseDemo.s.sol`
2. `SeedDemoPosition.s.sol`
3. `RaiseDepegSignal.s.sol`
4. `RunDepegScenario.s.sol` with confirmation only
5. `ReadRiskSnapshot.s.sol`
6. `RunDepegScenario.s.sol` with execution enabled
7. `ReadRiskSnapshot.s.sol`
8. `ResolveLocalEmergency.s.sol`
9. `ReadRiskSnapshot.s.sol`

The full step-by-step commands are in [docs/reviewer-demo.md](docs/reviewer-demo.md).

## Expected Consumer Semantics

### `Submitted` or `UnderReview`

- show as observable risk context;
- do not block new deposits automatically;
- do not affect exits.

### `Confirmed but not Executed`

- warn the consumer;
- do not claim the protocol is already restricted;
- do not reroute away yet.

### `Executed + PAUSE_DEPOSIT`

- block new deposits;
- continue allowing exits;
- reroute deposits to a safe alternative when available.

### `LocalRecovery after Executed`

- clear the active restriction surface;
- keep historical risk context observable;
- allow routing to resume.

### `Executed but State Mismatch`

- warn instead of pretending recovery;
- treat as a diagnostic state until responder state is inspected directly.

## Why The Router Does Not Re-Implement Policy

This PoC intentionally keeps the router thin.

The router does not reinterpret raw registry status and does not build its own restriction policy matrix. It consumes the output of `RiskAwareConsumerLens`, which is already derived from:

1. registry history;
2. responder truth;
3. execution consistency checks.

That separation is the whole point: consumers should read machine-usable state, not reverse engineer protocol-specific emergency logic on the fly.

## Test Coverage

Current tests cover:

- weak states that must not trigger live restrictions;
- confirmed execution that pauses deposits while keeping exits open;
- trusted registry enforcement;
- replay protection after local recovery;
- router behavior before confirmation, after confirmation, after execution, and after recovery;
- script guard rails for invalid inputs and no-route conditions.

Run the full test suite with:

```bash
forge test
```

## Scope Boundary

This repository is a PoC for one narrow design problem. It is not:

- a production incident response framework;
- a universal keeper network;
- an emergency exit or forced withdrawal standard;
- a replacement for protocol governance;
- a complete taxonomy or evidence schema standard.

## License

Released under the [MIT License](LICENSE).
