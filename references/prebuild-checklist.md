# Pre-build and pre-ship checklist

Use this as a gate. Every unchecked item becomes an explicit assumption, mitigation, or stop condition in the architecture note.

## Facts and capability

- [ ] Current network, chain ID, block cadence, precompile addresses, CoreWriter ABI/action encodings, token addresses, and compiler/library versions are recorded.
- [ ] Every historical protocol or tooling claim is marked verified, contradicted, or unresolved.
- [ ] An action capability matrix covers bridge, spot/perp conversion, leverage, order, activation, fees, and revocation.
- [ ] The example code’s address and simplified accounting are not being reused as production facts.

## State and accounting

- [ ] EVM, Core spot, Core perp, pending, and recovery states are separate in storage and in the indexer.
- [ ] Each asynchronous request has an ID, amount, initiator, expected route, status, timeout/expiry policy, and reconciliation path.
- [ ] EVM acceptance, Core settlement, and terminal failure are distinct user-visible statuses.
- [ ] Accounting is conservative during block-boundary gaps and cannot double-count pending funds.
- [ ] Signed perp equity, token balances, fees, and liabilities have explicit units, bounds, and negative-value behavior.
- [ ] A two-leg operation can partially complete without trapping the protocol in an unobservable state.

## Bridge and liveness

- [ ] Activation is tested on the target network, including missing activation.
- [ ] Fee assets, locations, reserves, top-ups, and depletion behavior are tested for every action and contract.
- [ ] Direct-to-perp routing can be detected as unavailable or redirected, with a tested fallback.
- [ ] Bridge liquidity/reserve exhaustion, delay, token issuer controls, and route changes are in the risk model.
- [ ] User exit works without the original frontend, RPC vendor, indexer, API wallet service, or team-operated retry bot.

## Reads and indexing

- [ ] Every read declares its block perspective and whether it is a raw precompile read, event-derived value, or live snapshot.
- [ ] Historical precompile-read behavior is verified for the exact RPC; no untested backfill assumption exists.
- [ ] Block `n`/`n+1` bridge-boundary results are compared across providers and against live transaction behavior.
- [ ] The indexer records source block, provider, observation time, schema version, and reconciliation status.
- [ ] Critical exits do not require a private indexer/API.

## Permissions and CROPS

- [ ] API-wallet and relayer permissions are least-authority, capped, expiring, revocable, and enforceable onchain or in the wallet layer.
- [ ] Admin, bridge, token issuer, RPC, indexer, frontend, API wallet, and operator powers are named with their failure and escape paths.
- [ ] Censorship Resistance: users can use direct contracts or an alternate client/provider for critical operations.
- [ ] Open/Free: contracts, frontend, adapter, indexer schema/config, ABIs, addresses, deployment steps, and license are reproducible and forkable.
- [ ] Privacy: public balances, counterparties, timing, RPC/IP metadata, API-wallet activity, and indexer telemetry are disclosed and minimized.
- [ ] Security: upgrades, approvals, keys, bridge liquidity, oracle/risk reads, recovery, and vendor liveness pass the walkaway test.

## Test and observability

- [ ] Unit, mock, property/invariant, fork/provider, and live small-value tests have separate claims.
- [ ] Delayed success, delayed failure, partial success, duplicate observation, provider disagreement, and fee/activation failures are covered.
- [ ] Events and dashboards distinguish request submitted, EVM accepted, Core observed, Core settled, Core failed, and recovery required.
- [ ] The protocol has a runbook for stuck funds that does not depend on editing storage or trusting an undocumented operator.
- [ ] A fresh environment can reproduce deployment, indexing, and recovery using pinned artifacts.

## Required architecture record

Finish with:

```md
## HyperEVM Precompile Architecture Record

Chosen default:
- <architecture and why>

Verified current facts:
- <fact, source, verification date>

Unresolved assumptions:
- <assumption, how to verify, stop condition>

Async state model:
- <states, transitions, caller/incentive, terminal proof>

Accounting invariant:
- <what is counted, what is pending, what is conservative>

Read/indexing plan:
- <block perspective, source of truth, reconciliation>

Permission and liveness model:
- <keys, API wallets, fee reserves, vendor dependencies, user exit>

Test evidence:
- <what each test layer proves>

Accepted compromises:
- <bounded compromises only>
```
