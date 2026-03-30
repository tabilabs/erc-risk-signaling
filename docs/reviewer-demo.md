# Reviewer Demo Runbook

This runbook is for reviewers who want to validate the PoC quickly on a local Anvil chain.

The goal is not to explain the full RFC. The goal is to reproduce these five states:

1. `Normal`
2. `Submitted`
3. `Confirmed without execution record`
4. `Confirmed + PAUSE_DEPOSIT active`
5. `LocalRecovery after execution`

It also shows:

1. how `RiskStateLens` and `RiskAwareConsumerLens` interpret the same signal differently across stages;
2. how `MockAggregatorRouter` consumes the consumer decision directly;
3. how deposits can be blocked while exits remain available.

## Prerequisites

1. `forge` and `cast` installed
2. `anvil` available locally
3. a local development key only; do not reuse the example key on a public network

## Step 0: Start Anvil

```bash
anvil
```

Open another terminal and enter the repository:

```bash
cd path/to/risk-signaling-response-poc
cp .env.example .env.local
source .env.local
```

## Step 1: Deploy the Demo Contracts

```bash
forge script script/DeployRiskResponseDemo.s.sol:DeployRiskResponseDemo \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Copy the printed addresses into `.env.local`:

```bash
export ASSET=<asset>
export REGISTRY=<registry>
export ADJUDICATOR=<adjudicator>
export EXECUTOR=<executor>
export ROUTER=<router>
export VAULT=<vault>
export SAFE_VAULT=<safeVault>
export LENS=<lens>
export CONSUMER=<consumer>

export TARGET="$VAULT"
export RESPONDER="$VAULT"
export ALTERNATE_VAULT="$SAFE_VAULT"
export EXIT_OWNER=$(cast wallet address --private-key "$PRIVATE_KEY")
```

The deployment script also prints `vaultTrustedRegistry` and `safeVaultTrustedRegistry`.
Both should match `REGISTRY`.

If you point `REGISTRY` at a responder-untrusted registry later, you may still observe a `Confirmed` report at the registry layer, but the vault must not enter emergency mode.

If you only want to inspect the lens and consumer output, you can omit `ALTERNATE_VAULT`.

If `ALTERNATE_VAULT` is set, `ReadRiskSnapshot.s.sol` will also attempt `selectDepositRoute(...)`. When every candidate is skipped, the router still reverts with `NoRouteAvailable()`, but the script converts that into explicit output instead of failing the whole read step.

## Step 2: Seed a Position

This makes the exit path observable later.

```bash
forge script script/SeedDemoPosition.s.sol:SeedDemoPosition \
  --rpc-url "$RPC_URL" \
  --broadcast
```

## Step 3: Read the Baseline State (`Normal`)

```bash
export REPORT_ID=0x0000000000000000000000000000000000000000000000000000000000000000

forge script script/ReadRiskSnapshot.s.sol:ReadRiskSnapshot \
  --rpc-url "$RPC_URL"
```

Expected output:

1. `reasonCodeLabel = NONE`
2. `shouldSkipVault = false`
3. `routerDecisionMatchesConsumer = true`
4. `selectedDepositRoute = VAULT`

## Step 4: Raise a Depeg Signal (`Submitted`)

```bash
forge script script/RaiseDepegSignal.s.sol:RaiseDepegSignal \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Copy the printed report id:

```bash
export REPORT_ID=<reportId>
```

Read again:

```bash
forge script script/ReadRiskSnapshot.s.sol:ReadRiskSnapshot \
  --rpc-url "$RPC_URL"
```

Expected output:

1. `registryStatusLabel = Submitted`
2. `reasonCodeLabel = NONE`
3. `shouldSkipVault = false`

## Step 5: Confirm Without Execution (`Confirmed without execution record`)

```bash
export TRIGGER_EXECUTION=false
export SKIP_CONFIRMATION=false

forge script script/RunDepegScenario.s.sol:RunDepegScenario \
  --rpc-url "$RPC_URL" \
  --broadcast
```

The script rejects two invalid cases:

1. `REPORT_ID = 0x0`
2. `SKIP_CONFIRMATION=true` with `TRIGGER_EXECUTION=false`

Read again:

```bash
forge script script/ReadRiskSnapshot.s.sol:ReadRiskSnapshot \
  --rpc-url "$RPC_URL"
```

Expected output:

1. `reasonCodeLabel = CONFIRMED_NOT_EXECUTED`
2. `shouldWarn = true`
3. `shouldSkipVault = false`
4. `selectedDepositRoute = VAULT`

Important: in the trust-anchor model, `CONFIRMED_NOT_EXECUTED` can mean either:

- the executor has not run yet; or
- the registry you are reading is not trusted by the responder.

That is why current restrictions must still be derived from the responder state.

## Step 6: Execute the Emergency Action (`Confirmed + PAUSE_DEPOSIT active`)

```bash
export TRIGGER_EXECUTION=true
export SKIP_CONFIRMATION=true

forge script script/RunDepegScenario.s.sol:RunDepegScenario \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Read again:

```bash
forge script script/ReadRiskSnapshot.s.sol:ReadRiskSnapshot \
  --rpc-url "$RPC_URL"
```

Expected output:

1. `reasonCodeLabel = PAUSE_DEPOSIT_ACTIVE`
2. `shouldBlockNewDeposit = true`
3. `routerShouldSkipVault = true`
4. `routerCanRouteExit = true`
5. `selectedDepositRoute = SAFE_VAULT`

## Step 7: Trigger Local Recovery (`LocalRecovery after execution`)

```bash
forge script script/ResolveLocalEmergency.s.sol:ResolveLocalEmergency \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Read again:

```bash
forge script script/ReadRiskSnapshot.s.sol:ReadRiskSnapshot \
  --rpc-url "$RPC_URL"
```

Expected output:

1. `reasonCodeLabel = LOCAL_RECOVERY_WITH_HISTORY`
2. `shouldSkipVault = false`
3. `routerShouldSkipVault = false`
4. `selectedDepositRoute = VAULT`

This is the clean recovery path: the responder no longer exposes an active restriction and the active report id has been cleared.

If you see `EXECUTED_STATE_MISMATCH` instead, execution history and responder state no longer line up cleanly. The script should not guess that recovery has already happened.

## Expected Event Sequence

Typical event order:

1. `SignalRaised`
2. `SignalResolved`
3. `ExecutionTriggered`
4. `SignalExecutionRecorded`
5. `EmergencyActionExecuted`
6. `LocalEmergencyResolved`

These events are PoC instrumentation. They do not imply that a final standard must require an identical event surface.

In this PoC, the `resultHash` carried by `SignalExecutionRecorded` and `EmergencyActionExecuted` is a post-execution responder state anchor, not a generic before/after diff format.

## Diagnostic State: `EXECUTED_STATE_MISMATCH`

Meaning:

- the registry still exposes a confirmed report with recorded execution history;
- the responder no longer exposes the same state implied by that execution fact.

Interpretation:

- this may come from local recovery with retained historical execution facts;
- it may also come from implementation drift or a non-happy-path state transition.

Handling:

- do not automatically reinterpret it as `LOCAL_RECOVERY_WITH_HISTORY`;
- inspect `emergencyStatus()`, `activeReportId`, and `restrictionIds` directly.

## Common Problems

### `BondTooLow`

- Cause: `BOND` is below the registry `BOND_FLOOR`
- Fix: restore the default `BOND=100000000000000000` in `.env.local`

### `ReportNotConfirmed`

- Cause: execution was attempted before confirmation
- Fix: run Step 5 before Step 6

### `ReportAlreadyProcessed`

- Cause: the same `REPORT_ID` was executed twice
- Fix: raise a new signal instead of replaying the same report

### `routerCanRouteExit = false`

- Cause: `SeedDemoPosition.s.sol` was not run, or `EXIT_OWNER` is not the share owner
- Fix: complete Step 2 and set `EXIT_OWNER` from the same `PRIVATE_KEY`

### `NoRouteAvailable`

- Cause: every candidate vault was skipped
- Router behavior: `MockAggregatorRouter` still reverts with `NoRouteAvailable()`
- Script behavior:
  - `routerHasSelectedDepositRoute = false`
  - `routerNoRouteAvailable = true`

Common misconfigurations:

1. `ALTERNATE_VAULT` points back to the risky vault
2. `ALTERNATE_REPORT_ID` also causes the alternate vault to be skipped

Fix:

1. remove `ALTERNATE_VAULT` if you only want lens and consumer output
2. set `ALTERNATE_VAULT="$SAFE_VAULT"` and keep `ALTERNATE_REPORT_ID=0x0` if you want to observe rerouting
