# Preconditions, bridges, and permissions

Use this reference when the protocol moves USDC or other assets between HyperEVM and HyperCore, places or manages perp positions, or delegates actions to an API wallet.

## Build a capability and precondition matrix

Do not hide preconditions in a deploy script. Keep a versioned matrix like this in the repo and update it when the network or library changes:

| Capability | Caller | EVM precondition | Core precondition | Fee source | Async failure | Fallback / exit |
|---|---|---|---|---|---|---|
| EVM → Core spot/perp bridge | contract or approved caller | current bridge ABI and route | account activated; required Core balance | verify current HYPE/USDC rule | route disabled, insufficient liquidity, validation mismatch | alternate route or pending recovery |
| Core perp → spot | contract/API wallet | current CoreWriter encoding | valid account and asset state | verify current fee rule | partial completion | spot recovery |
| Core spot → EVM bridge | contract/API wallet | destination and token config | spot funds and bridge liquidity | verify current fee rule | bridge delay or reserve exhaustion | retry/status/alternate exit |
| leverage or order action | permitted signer | current action support | margin, permissions, and risk checks | verify current fee rule | rejected or delayed order | cancel/close/revoke path |

The exact rows, action names, fee assets, and activation requirements are network-versioned facts. A blank cell is an unresolved risk, not permission to assume success.

## Activation and fee management

Treat activation and fee funding as separate HyperCore preconditions. A smart contract may need activation on its Core account before CoreWriter Actions work, and Core→EVM and EVM→Core routes may require different fee balances. Multiple contracts can create a top-up web; verify the current rules instead of assuming one shared balance.

Before launch, verify and document:

- what “activated” means today, which account must be activated, the minimum/current amount, and whether activation can expire or be revoked;
- the fee asset and balance location for each action and route;
- whether the protocol's contract, a treasury, or an API wallet pays the fee;
- how each contract is topped up without a privileged operator becoming a liveness dependency;
- alert thresholds, rate limits, and what users see when the fee reserve is empty;
- whether a fee top-up can be griefed, redirected, or confused with user funds.

Keep fee reserves separate from user accounting. Test depletion and restoration, not only the funded happy path.

## USDC bridge risk

Two integration hazards require explicit modeling:

1. A Circle bridge function named `disableDexForwarding` may disable direct forwarding to a perp balance and route funds to spot instead. This function name and behavior must be verified against the current deployed bridge. Design a feature probe and an alternate spot-to-perp path rather than assuming direct perp forwarding is permanent.
2. The HyperEVM↔HyperCore bridge may not be backed 1:1 at all times. Reserve exhaustion can make a Core-to-EVM bridge fail even when the Core balance exists. Do not build liquidation, redemption, or collateral assumptions that require immediate bridge settlement.

Model issuer and bridge controls explicitly: token freezing/blacklisting, reserve custody, route changes, rate limits, delays, and the user’s ability to recover on the originating domain. Failure should be a visible state with a recovery path, not an unbounded retry loop.

## API-wallet architecture

CoreWriter capability gaps can force a hybrid design: a vault-like strategy may need spot bridging, spot↔perp conversion, leverage updates, and order creation while one or more actions are unavailable to CoreWriter or API wallets. Assign each operation to the least-authority actor that can perform it, and verify the current action matrix before choosing the split.

Treat this as a capability-gap pattern, not a current API-wallet specification:

- verify current API-wallet creation, authorization, history, action, and revocation rules;
- assume the architecture may need a hybrid contract/API-wallet path until live tests prove otherwise;
- define the exact operations an API wallet may call and enforce caps, symbols, leverage limits, expiry, nonce/replay rules, and revocation outside the prompt or backend;
- separate user funds from fee reserves and API-wallet operating funds;
- provide a contract-only or direct-user escape for withdrawal, revoke, and close-position flows;
- make vendor/operator disappearance survivable: users must not need the original API service to recover funds;
- never put a private API-wallet key in a frontend, commit it to the repository, or grant it more authority than the smallest action scope.

No prior Core history may be a creation precondition for an API wallet. Verify this before designing account provisioning, and test both fresh and previously used keys.

## Permissions review

For each contract, signer, relayer, and API wallet, record:

- who can initiate actions;
- which assets and accounts can be touched;
- maximum amount, leverage, frequency, and duration;
- how permissions expire and are revoked;
- what happens if the key is lost, compromised, censored, or unavailable;
- whether a user can exit without that actor.

Use least authority. A backend that “usually checks” limits is not a security boundary. Put enforceable limits in the contract, wallet, or signer policy, and make the failure mode conservative.
