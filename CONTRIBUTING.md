# Contributing

Thanks for contributing.

## Development Setup

1. Install Foundry.
2. Clone the repository.
3. Run:

```bash
forge build
forge test
```

## Scope

This repository is a narrow PoC for the proposed risk signaling and response interface.

Good contributions usually fall into one of these buckets:

- correctness fixes for the signal, execution, or recovery flow;
- clearer English documentation for reviewers;
- tighter tests around state transitions and consumer semantics;
- better demo ergonomics that do not expand protocol scope.

## What To Avoid

- adding production-only infrastructure;
- expanding the PoC into a full governance or keeper framework;
- introducing standard requirements that belong in the ERC discussion rather than the PoC;
- mixing unrelated protocol experiments into this repository.

## Pull Request Expectations

Please keep changes small and include:

1. a clear problem statement;
2. the design tradeoff behind the change;
3. updated tests when behavior changes;
4. updated docs when the reviewer flow changes.
