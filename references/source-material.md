# Evidence map and verification policy

## Historical context

This skill incorporates lessons from a January 2026 HyperEVM integration report. The report described precompile reads, CoreWriter actions, cross-domain bridges, API-wallet delegation, RPC behavior, and local tooling. The guidance below preserves the engineering lessons without depending on external artifacts or accompanying media.

These lessons are historical observations, not protocol specifications. Treat concrete addresses, function names, fee rules, API-wallet limitations, provider behavior, and tooling behavior as claims that require current verification.

## Current verification targets

Verify historical observations against current primary material before implementation:

- Hyperliquid developer docs: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore
- HyperEVM overview and network configuration: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm
- `hyper-evm-lib` source, examples, simulator, and security notes: https://github.com/hyperliquid-dev/hyper-evm-lib

The current library documentation advertises local simulation for precompile calls, CoreWriter actions, and EVM↔Core bridging. Pin the release and inspect its coverage, then retain live small-value tests for real block ordering, bridge liquidity, fee/activation behavior, RPC semantics, and liveness.

## Topic-to-guidance map

| Topic or visual model | Standalone concept and guidance |
|---|---|
| Bridge/accounting example | A minimal contract combines an EVM token balance with a Core account-value read. Use it only as a teaching model; verify addresses, signed values, pending accounting, and double-counting assumptions before reuse. |
| Atomic versus asynchronous execution | A request can be accepted by EVM execution while its CoreWriter action remains pending or later fails. Model acceptance, processing, settlement, failure, and recovery separately. |
| EVM block `n`/`n+1` timing visual | A timeline shows an EVM request accepted during block `n`, the EVM balance reduced immediately, the Core balance unchanged during the pending interval, and the Core credit appearing after asynchronous processing. It conveys that request acceptance and settlement are different events. |
| USDC route and liquidity behavior | Bridge routing, backing reserves, issuer controls, and route flags are runtime dependencies. Probe the current route, detect redirection, and provide recovery when liquidity or routing changes. |
| Activation and fee flow | A dependency diagram connects each caller and action to its activation state, fee asset, fee location, reserve owner, top-up path, alert, and restoration procedure. It conveys that EVM gas alone does not fund every CoreWriter operation. |
| Historical reads and indexing visual | A data-flow diagram separates event-derived history, live block snapshots, and latest-only precompile reads. It conveys that a latest read must not be presented as historical data and that parameterized snapshots may not scale to every account. |
| Two-leg Core-to-EVM flow visual | A flow diagram shows `perp → spot` followed by `spot → EVM`, with independent success and failure branches after each step. It conveys that the first leg can succeed while the second leaves funds in spot and needs recovery. |
| RPC block-boundary visual | Two adjacent boxes represent transaction-visible execution and an RPC block-tag snapshot, with a boundary interval between them. It conveys that provider observations can disagree about an intermediate state without proving loss. |
| API-wallet capability model | A capability matrix maps each operation to the least-authority actor that can perform it, with caps, expiry, revocation, and a direct-user escape. It conveys that missing CoreWriter actions may require a hybrid contract/API-wallet design. |
| Tooling and provider coverage visual | A layered stack shows mocks, forks, simulators, RPC providers, and live network tests, with coverage gaps between layers. It conveys that local tools accelerate iteration but live small-value tests validate production semantics. |

## Evidence labels

Use these labels in architecture notes:

- **Historical observation** — behavior described by the dated integration report; useful context, not a current guarantee.
- **Derived guardrail** — engineering guidance inferred from an observation, such as treating a two-leg bridge as a state machine.
- **Current fact** — verified against current official docs, deployed code, chain configuration, or live experiments; include date and verification target.
- **Unresolved** — not yet verified; do not build a safety-critical assumption on it.

When current evidence conflicts with a historical observation, record the current fact, preserve the underlying risk class when it still applies, and update the affected capability matrix or test case.
