# EthMagicians Opening

This file contains the current forum-opening copy for the proposed `Risk Signaling and Response Interface`.

Use the post below as the default `EthMagicians` topic body.

## Final Paste-Ready Post

```text
[Draft ERC] Risk Signaling and Response Interface

Hi all, I would like to share a draft for a Risk Signaling and Response Interface aimed at DeFi protocols, wallets, aggregators, and other external consumers.

The problem this draft is trying to solve is not how to give every protocol another pause button. Most major protocols already have pause, freeze, or guardian-style controls. The missing layer is a common, machine-readable interface for answering: what risk has been reported, what has been confirmed, and what restriction surface is the protocol currently exposing to the outside world.

The intended placement is deliberately narrow. This is not a pre-admission wallet permission system, and it is not an execution-mandate standard by itself. It is a signaling bus plus response-discovery layer that can sit between upstream risk producers and downstream consumers.

The key design choice is that confirmed risk history and live protocol restrictions are intentionally separated. The registry records what was reported and what was confirmed. The responder exposes what restrictions are actually active now. This matters because a protocol may recover locally and reopen normal flows without erasing the historical fact that a risk event occurred.

A few V1 boundaries are especially important:

- this is not an `Emergency Exit` or forced withdrawal standard;
- the registry, reporters, and executors do not receive direct control over protocol funds;
- `Submitted` and `UnderReview` are observable states, but MUST NOT automatically trigger protective actions;
- external consumers should treat the protocol responder as the source of truth for current restrictions, while the registry remains the bus for reported and confirmed history;
- `dependencyRef` in core V1 is intentionally limited to single-hop dependency expression;
- atomic `0-day` response, complete keeper networks, and unified reward curves are explicitly out of scope for the first version.

The current design also prefers asynchronous execution: adjudicators update registry state, and executors or keepers trigger responder hooks separately. The goal is to avoid making confirmation itself depend on a successful push call into an arbitrary protocol, while still preserving a minimal machine-readable discovery surface for confirmed-but-not-yet-consumed reports.

At this stage, I am also intentionally treating `riskType` taxonomies and structured `evidenceRef` schemas as follow-on work rather than Core V1 requirements. I would especially value feedback on whether that is the right level of restraint for a first version.

The feedback I would most value at this stage is:

1. whether the current `registry bus + responder source-of-truth` split feels like the right minimal boundary;
2. whether V1 should require a minimal machine-readable discovery surface for confirmed-but-not-yet-consumed reports under async execution;
3. whether `adjudicator` trust and latency should remain fully implementation-defined in V1, or need a stronger common framing for consumers;
4. whether `riskType` taxonomy and structured evidence guidance should remain extensions rather than Core requirements in a first version.

Reference PoC:
- Repository: https://github.com/tabilabs/erc-risk-signaling
- Suggested reviewer path: README -> docs/reviewer-demo.md -> docs/spec-map.md -> docs/submission-pack.md
```

If you also want to expose a public draft link in the forum topic, add one line immediately before `Reference PoC`:

```text
- Draft: https://github.com/tabilabs/erc-risk-signaling/blob/main/docs/erc-draft.md
```
