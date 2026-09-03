# Reads, indexing, testing, and tooling

Use this reference when a protocol needs historical charts, TVL, account pages, deployment scripts, maintenance calls, or confidence that a local test represents HyperEVM behavior.

## Historical precompile reads

Historical provider behavior shows that an RPC may answer many latest precompile reads while failing to query a smart-contract view containing a precompile at a historic block. Traditional indexers that backfill by replaying historic view calls therefore may fail for those fields.

Verify this behavior against the exact current RPC and precompile. Until proven otherwise:

- label each read as `latest`, `historical`, `event-derived`, or `live-snapshot`;
- never let a UI silently imply that a latest read is a historic value;
- use event logs for transitions and an event-first indexer for reconstructable state;
- for non-event precompile values, snapshot them at the live block cadence required by the product and store block number, timestamp, provider, and schema version;
- document gaps, missed blocks, provider changes, and reconciliation rules;
- test parameterized per-user reads separately from global values; a per-block snapshot of every account may not scale.

A live snapshot database is an operational dependency. Publish its schema, code/configuration, export format, and a self-host or alternate-provider path. Do not make the frontend depend on an opaque hosted API for critical exit actions.

Use the current `L1Read.sol` and `CoreWriter.sol` definitions rather than hand-copying action bytes from an example. The [official Hyperliquid developer documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore) describes versioned CoreWriter encoding and warns that invalid precompile inputs can return an error while consuming all gas passed to the precompile call frame. Validate token/market/account indices and other inputs before making the call, and include invalid-input behavior in gas and failure tests.

## RPC boundary semantics

Different RPC implementations may return anomalous one-block values, including zero for spot or perp balances around bridge settlement. This is not a license to hard-code one provider’s quirk.

Create an RPC compatibility matrix for the current network:

- `latest` and explicit block-tag reads;
- `eth_call` before, within, and after a bridge transaction;
- pending, successful, failed, and partially completed CoreWriter operations;
- at least two providers plus a self-hosted or direct-node option where available;
- latency, rate limits, reorg/retry behavior, and response errors.

If a risk decision consumes a precompile read, state which block perspective is required. If the provider cannot supply it, fail closed or use a proven conservative reconstruction.

## Testing strategy

Separate what local tests prove from what they do not:

| Test layer | It can prove | It cannot prove |
|---|---|---|
| Pure Solidity/unit tests | local accounting, state transitions, caps, idempotence | live precompile values or CoreWriter processing |
| Mocks | handling of encoded success/failure/latency cases | that mocks match current HyperCore behavior |
| Fork/RPC tests | integration with a captured chain/provider state | future async behavior, provider quirks, or unavailable historical reads |
| Live small-value tests | current action encoding, activation, fees, settlement, and failure surfaces | safety for arbitrary size or every future network change |
| Invariant/property tests | no double credit, conservative accounting, bounded permissions | external system honesty or liveness |

Build a live integration harness with disposable contracts/accounts, tiny balances, deterministic request IDs, event capture, retry/reconciliation tooling, and a kill switch that cannot trap user funds. Test:

- EVM acceptance followed by Core success;
- EVM acceptance followed by Core rejection;
- first leg success / second leg failure;
- bridge route disabled or redirected to spot;
- bridge reserve or fee balance depleted;
- activation missing or delayed;
- settlement across EVM blocks `n` and `n+1`;
- negative or adverse perp account value;
- duplicate events, missed observations, RPC timeout, and provider disagreement;
- API-wallet revocation, fresh-key provisioning, previously used key, and operator disappearance.

Foundry support for genuine precompile simulation and precompile reads from scripts can be incomplete. Current `hyper-evm-lib` documentation advertises a local simulator for precompile calls, CoreWriter actions, and EVM↔Core bridging, so treat tooling limitations as version-specific rather than permanent. Inspect the pinned simulator release and its covered actions, failure modes, block ordering, and known gaps. A simulator can improve iteration but is not evidence that the live system, RPCs, bridge reserves, fees, or operator dependencies behave identically. If deployment or maintenance still needs JavaScript/Python because the Solidity-native path cannot read the precompile, isolate that adapter, pin versions, and test it on the target network.

## Tooling and provider posture

Alchemy, QuickNode, Ponder, HypeRPC, LiFi, and `hyper-evm-lib` are examples of providers or libraries used in prior integrations. Preserve them as historical examples, not endorsements or a current compatibility list.

Prefer:

- a small provider adapter with capability probes rather than SDK calls scattered through business logic;
- pinned library and compiler versions with ABI/address manifests;
- a fallback RPC and a documented self-host/direct-call path;
- live health checks for action submission, precompile reads, indexing freshness, and fee reserves;
- alerts that distinguish “EVM receipt received” from “Core state settled.”

Do not let a private RPC, indexer, support channel, frontend host, or library maintainer become the only path for withdrawals or recovery. Documentation gaps and incomplete provider coverage are possible; budget time for implementation inspection and live experiments instead of assuming ordinary EVM tooling transfers unchanged.
