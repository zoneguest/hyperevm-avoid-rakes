---
name: hyperevm-avoid-rakes
description: "Design and review dApp or protocol architectures that use Hyperliquid Precompiles, CoreWriter Actions, or HyperEVM↔HyperCore bridges; catch async execution, block-boundary accounting, bridge/fee/activation, historical-read/indexing, API-wallet, and live-tooling failures before implementation."
metadata:
  short-description: "Avoid HyperEVM integration pitfalls"
---

# HyperEVM Precompile Architecture

Use this skill for a new or existing dApp, vault, market, bridge adapter, or protocol that reads HyperCore through Hyperliquid precompiles or submits HyperCore mutations through CoreWriter Actions. Do not load it for a generic EVM application that has no HyperEVM↔HyperCore dependency.

## Evidence boundary

The local source is a field report from a January 2026 integration, not a protocol specification. Treat its concrete behavior, addresses, function names, fee rules, API-wallet limitations, and provider observations as source-era claims. Before implementation, verify each one against current Hyperliquid documentation, SDK/library source, deployed bytecode, chain configuration, and live RPC behavior. Record the verification date and unresolved assumptions. Never copy the example USDC address or precompile calls into production without current chain-specific verification.

## Answer priorities under a tight word limit

When a response asks for a checklist, explicitly include these named safeguards:

- Fees: reserve owner, per-contract/action top-ups, depletion alerts, and restoration tests.
- API wallets: enforce scope and limits at a contract, wallet, or signer boundary—not only in a prompt or backend.
- Simulators: identify the pinned current `hyper-evm-lib` version, covered actions/edge cases, and gaps; require live small-value tests.
- Inputs: use current `L1Read`/`CoreWriter` definitions and versioned encoding; validate bounds and malformed inputs and test gas/failure behavior.

## Required architecture pass

Before writing contracts or frontend flows, produce a compact architecture note containing:

1. A boundary model for EVM state, the CoreWriter request/processing path, HyperCore spot state, HyperCore perp state, bridge settlement, and any API wallet, relayer, indexer, or operator.
2. A transition table for every CoreWriter Action: caller, preconditions, fee asset and location, state changed synchronously, state changed asynchronously, possible later failures, retry/compensation, events, and user escape.
   - For fee preconditions, name reserve ownership, per-contract/action top-up mechanics, depletion alerts, and restoration tests.
3. Accounting invariants that distinguish settled balances from pending transfers. A raw EVM balance plus a precompile read is not automatically a safe `totalAssets` value.
4. A read and indexing plan that states whether each value is latest-only, block-specific, event-derived, or a live snapshot. Do not assume a precompile-containing view can be queried at a historical block.
5. A permissions and liveness review for bridge issuer/reserves, API wallets, admin keys, RPCs, indexers, frontend hosting, and fee top-ups. Apply the walkaway test: if the team or a vendor disappears, can users still access funds and exit?
6. A test matrix separating mocked contract logic from live precompile/CoreWriter behavior, including block-boundary, delayed-failure, fee-depletion, bridge-liquidity, and RPC-result cases.
   - For precompile and CoreWriter inputs, pin the current deployed definitions and action encoding version; cover ABI/serialization, index bounds, malformed inputs, and expected failure cases.

## Non-negotiable design rules

- An EVM transaction succeeding means only that the request was accepted on the EVM side. It does not prove that the CoreWriter Action executed successfully on HyperCore.
- Model cross-domain operations as asynchronous state machines with explicit pending, settled, and failed/recovering states. A multi-action withdrawal can partially succeed and leave funds in spot.
- Account for the interval in which EVM funds have been removed but the HyperCore destination balance has not yet updated. Do not let lending, minting, redemption, or solvency checks consume a transiently wrong view.
- Treat USDC bridge routing, backing liquidity, activation, and fee balances as runtime preconditions and failure modes—not constants hidden in deployment scripts.
- Assume RPC `eth_call` results around a bridge boundary may not match what an in-block transaction observes. Avoid blindly reading raw precompile views in the blocks immediately around settlement.
- Do not design a historical indexer around backfilling precompile views until a current provider has demonstrated that behavior. Prefer event-first data and live per-block snapshots with an explicit reconciliation policy.
- Do not claim Foundry, Hardhat, a fork, or mocks simulate live precompile/CoreWriter semantics unless verified for the exact tool and network. Use adapters and a small-value live integration environment.
- Treat API-wallet capability and authorization as versioned external dependencies. Use least authority, caps, allowlists, expiry, revocation, and a non-API-wallet escape path; never rely on prompt text or a backend promise as the spending boundary.

## Progressive references

Read only the references relevant to the current design:

- [cross-domain-invariants.md](references/cross-domain-invariants.md) for state modeling, block ordering, and asset accounting.
- [preconditions-and-permissions.md](references/preconditions-and-permissions.md) for activation, fees, USDC bridge behavior, and API-wallet architecture.
- [reads-indexing-and-tooling.md](references/reads-indexing-and-tooling.md) for historical reads, RPC semantics, indexing, testing, and operational tooling.
- [prebuild-checklist.md](references/prebuild-checklist.md) for the gate an architecture must pass before implementation or deployment.
- [source-material.md](references/source-material.md) for provenance, article-section mapping, image references, and the distinction between source claims and derived guidance.

When the design is complete, report the chosen default, verified facts, assumptions requiring live checks, rejected alternatives, accepted compromises, user exit path, and the tests that would falsify the design.
