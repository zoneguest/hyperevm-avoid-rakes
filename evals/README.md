# HyperEVM skill evals

This eval measures whether `hyperevm-avoid-rakes` improves a naive agent's answers on the integration failures identified in the captured Hyperliquid field report.

The design follows the requested `ethskills-evals` pattern—YAML cases, expected facts, fail conditions, an independent judge, and paired with/without measurements—with two additions for this risk-sensitive skill:

- every case names the rake problem and relevant reference files;
- source-era claims, critical safety failures, weights, paired deltas, and a pre-registered success gate are explicit.

Run the model- and harness-neutral contract in [runner/eval-runbook.md](../runner/eval-runbook.md). The included [runner/run_luna.md](../runner/run_luna.md) is the concrete Luna Medium (`gpt-5.6-luna`, reasoning effort `medium`) pilot profile. Aggregate judgments with [runner/score.py](../runner/score.py).

The eval cases and hidden rubric are in [hyperevm-precompiles.yaml](hyperevm-precompiles.yaml). Before each run, generate the blind target packet with `python3 runner/export_prompts.py evals/hyperevm-precompiles.yaml evals/prompts.json`. The target must receive only [prompts.json](prompts.json), never the rubric YAML; validate returned JSONL with [validate_responses.py](../runner/validate_responses.py). The suite covers 17 rake problems, including async receipt semantics, partial bridge completion, transient accounting, RPC perspective, historic reads, USDC route/liquidity, activation/fees, signed equity, API wallets, tooling, invalid inputs, incentives, CROPS, and source freshness.
