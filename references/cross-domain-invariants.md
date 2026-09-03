# Cross-domain invariants

This reference provides a standalone implementation model for cross-domain precompile and CoreWriter integrations. Verify exact precompile and CoreWriter semantics against the current network before coding.

## Model four ledgers, not one balance

At minimum, separate:

- EVM token balance: what the contract currently holds on HyperEVM.
- HyperCore spot balance: what is settled in the user's or contract's spot account.
- HyperCore perp state: margin, account value, positions, and liabilities. Treat account value as signed/risk-bearing data, not as an ERC-20 balance.
- Pending cross-domain operations: requests accepted on EVM but not yet settled, plus operations that settled one leg and still need reconciliation.

A simple teaching contract may compute `totalAssets` from an EVM USDC balance and an Account Margin Summary read. That is not a safe production accounting formula. Define how negative perp equity, pending transfers, unrealized PnL, fees, haircuts, and insolvency are handled. Do not cast a potentially negative signed account value to `uint256` and add it to a token balance without an explicit policy.

## CoreWriter is a message boundary

For every action, document at least these states:

```text
REQUESTABLE → EVM_ACCEPTED → CORE_PROCESSING → SETTLED
                                      ├──────→ FAILED
                                      └──────→ PARTIAL / RECONCILIATION_REQUIRED
```

The EVM call can revert for local validation or succeed while the later HyperCore action fails. A receipt proves the EVM transition, not the terminal state. Emit a local request identifier and store enough information to reconcile the corresponding Core-side result.

For each transition answer:

1. Which ledger changes immediately in the EVM transaction?
2. Which ledger changes only after CoreWriter processing?
3. What event or observable state proves the terminal result?
4. What happens if validation differs between EVM and HyperCore?
5. Who pays for retries or cleanup, and why will they do it?
6. Can the user withdraw or otherwise exit while the request is pending?

## Bridge-to-perp timing

A `bridgeToPerp` flow illustrates the dangerous interval:

| Phase | EVM USDC | HyperCore perp balance | Safe interpretation |
|---|---:|---:|---|
| Before request | settled | settled | ordinary accounting |
| After EVM call in block `n` | reduced | not yet increased | amount is pending, not lost or settled |
| After Core processing | reduced | increased if successful | settled only after proof/reconciliation |
| Async failure | reduced or refunded according to current behavior | unchanged or otherwise defined | enter a recovery state; do not assume automatic refund |

If a share price, `totalAssets`, collateral value, borrow limit, or redemption path reads only the two settled ledgers, it can temporarily understate or misstate value. Choose one explicit policy:

- include a bounded, recorded pending amount in accounting while preventing double use;
- mark pending assets unavailable and make the UI/risk engine show the delay; or
- use another conservative policy with a documented solvency proof.

Do not silently count an optimistic future Core balance.

## Perp-to-EVM timing and partial completion

A return path can use two actions: move USDC-class funds from perp to spot, then bridge spot to EVM. The first can succeed while the second fails. That leaves funds in spot and invalidates a one-transaction mental model.

Represent the legs separately. A robust flow has:

- an operation ID and immutable requested amount;
- a state for `perp_to_spot_pending`, `spot_settled`, `spot_to_evm_pending`, `complete`, and `recovery_required`;
- reconciliation based on current Core state and events, not only the original EVM receipt;
- a permissionless or economically incentivized retry/cleanup path where possible;
- a user-visible escape that does not require the original frontend or operator.

Two useful visual models for reviewing the state machine are:

- **Bridge-to-Core timing:** a horizontal timeline shows an EVM request accepted during block `n`, the EVM balance reduced immediately, the Core balance unchanged during the pending interval, and the Core credit appearing only after asynchronous processing. It emphasizes that acceptance and settlement are separate points in time.
- **Two-leg Core-to-EVM flow:** a flow diagram shows `perp → spot` as the first arrow and `spot → EVM` as the second arrow, with separate success/failure branches after each arrow. It emphasizes that the first leg can succeed while the second leaves funds in spot and requires recovery.

## Block-boundary read rule

A bridge may transfer funds to EVM at the start of a block. In a conceptual flow, funds can disappear between blocks and reappear at the start of the next block. An RPC provider cannot generally return the exact perspective of an EVM transaction inserted partway through a block, so a view may report zero or an otherwise surprising combination of spot and perp balances around `n`/`n+1`.

Treat `eth_call` at a block tag as a provider-defined snapshot, not as a universal replay of every intra-block transition. For values with solvency or minting consequences:

- record the action and expected settlement block;
- avoid raw reads in the affected boundary window, or adjust them with a proven reconciliation layer;
- compare live transaction behavior with RPC snapshots from more than one provider;
- make the policy explicit in contracts, indexers, and frontend copy.

A useful visual for this is a Schrödinger-box diagram: one box represents the smart contract's transaction-visible execution, another represents the RPC provider's block-tag snapshot, and a boundary between them marks the unresolved intermediate state. The relationship it conveys is that execution and RPC interpretation can disagree without either observation proving funds were lost.

## Invariants worth proving

Adapt these to the protocol rather than copying them blindly:

- A request is never counted as settled in both its source and destination ledgers.
- A failed or partially completed request remains discoverable and recoverable; it cannot disappear from accounting because a receipt succeeded.
- No action can spend the same pending amount twice.
- A view used for solvency, exchange rate, collateral, or redemption is conservative across the worst permitted delay and failure path.
- Every state transition has a caller, a gas/fee source, and a reason for execution; there is no implicit scheduler.
- Signed perp equity, token balances, pending transfers, fees, and protocol liabilities use units and signs that are checked separately.
- Reconciliation is idempotent: observing the same Core event or state more than once cannot credit funds twice.
