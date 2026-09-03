# Harness-neutral eval runbook

This is the portable execution contract for the HyperEVM architecture evals. It defines the suite inputs, target-output format, judging boundary, and scoring commands without selecting a target model, agent framework, or orchestration harness.

Keep the evaluation layers separate:

- **Target packet** — public prompts only.
- **Skill bundle** — `SKILL.md` plus the references supplied to the skill condition.
- **Evaluator** — the rubric YAML, judge prompt, and scorer; never expose these to target agents.
- **Run profile** — model, harness, tool policy, and other environment settings; record these outside the suite definition.

## Stable suite contract

The following are fixed for a comparable run:

- the case IDs and prompts in `evals/hyperevm-precompiles.yaml`;
- the hidden expected facts, fail conditions, weights, and success gate;
- the two conditions: baseline and with skill;
- the exact target response schema;
- paired case/replicate coverage;
- the deterministic aggregation performed by `runner/score.py`.

The following are configurable and must be recorded in a run manifest:

- target and judge model/provider;
- agent harness and version;
- system prompt, reasoning settings, sampling settings, and seed, if supported;
- tools and network access;
- context-injection method;
- concurrency, timeout, and retry policy.

If any of those settings differ between baseline and with-skill, the run no longer isolates the skill effect.

## 1. Export the blind target packet

Run from the skill directory:

```bash
python3 runner/export_prompts.py \
  evals/hyperevm-precompiles.yaml \
  evals/prompts.json
```

Give target agents only `evals/prompts.json`. Do not expose the full YAML: its `expected_facts`, `fail_if`, `rake_problem`, weights, and reference routing would leak the evaluation criteria.

## 2. Implement the harness adapter

For every replicate, invoke the same harness twice with fresh contexts:

- **baseline** — the blind prompt packet and the common system/output instructions; no HyperEVM skill, article capture, rubric, or skill references;
- **with_skill** — the same packet, system/output instructions, and target configuration, plus `SKILL.md` and the reference files relevant to each case.

Keep model settings, available tools, web access, prompt order, and answer limits identical. A recommended default is to disable web access in both conditions when measuring the value of the supplied skill material.

The adapter may mount files, inject their contents, or use the harness's native skill mechanism. It must not change the target task. A useful abstract interface is:

```text
run(condition, prompt_packet, context_bundle, run_config) -> response JSONL
```

The adapter should keep logs and progress output out of the response file. If a harness returns Markdown, tool traces, or a single aggregate object, convert it in the adapter before validation.

## 3. Target response contract

Write exactly one JSON object per prompt, in the packet's order, with exactly these fields:

```json
{"case_id":"async-receipt-not-settled","answer":"..."}
```

The answer must be a non-empty string. Store one file per condition, for example:

```text
results/<consumer>/replicate-1/baseline.jsonl
results/<consumer>/replicate-1/with_skill.jsonl
```

Validate before judging:

```bash
python3 runner/validate_responses.py \
  --packet evals/prompts.json \
  results/<consumer>/replicate-1/with_skill.jsonl \
  results/<consumer>/replicate-1/baseline.jsonl
```

Do not repair missing or reordered answers by hand; fix the adapter and rerun the condition.

## 4. Judge independently

Use a fresh judge context with [judge.md](judge.md). Supply the case prompt, one target response, and the hidden rubric fields needed for that case. Do not supply the target skill to the judge. Prefer judging responses independently with anonymized condition labels so the judge cannot reward a condition by name.

Store one judgment per condition, case, and replicate. The normalized form is:

```json
{
  "condition": "with_skill",
  "replicate": 1,
  "case_id": "async-receipt-not-settled",
  "score": 2,
  "critical_failure": false,
  "fail_triggers": []
}
```

The scorer also accepts the paired format used in the pilot. Audit every critical failure and sample passes against the YAML rubric; document any corrected judgment.

## 5. Score the paired run

```bash
python3 runner/score.py \
  results/<consumer>/judgments.json \
  --cases evals/hyperevm-precompiles.yaml
```

For multiple replicates, combine all normalized judgment records in `results/<consumer>/judgments.json` and preserve the `replicate` number. The scorer checks duplicate rows, invalid scores, fail-condition consistency, and complete baseline/with-skill coverage before calculating:

- weighted normalized score;
- absolute uplift in percentage points;
- paired improvement rate;
- critical-case pass rate;
- per-rake deltas and regressions;
- replicate means and population standard deviations.

The pre-registered suite gate is:

1. With-skill score is at least 80%.
2. With-skill exceeds baseline by at least 20 percentage points.
3. Critical-case pass rate improves by at least 25 percentage points.
4. No critical rake has a mean delta below −0.25 on the 0–2 scale.

Run at least three paired replicates for a stable claim. A single replicate is a smoke test.

## 6. Compare consumers correctly

To evaluate another harness, run both conditions inside that harness and calculate uplift within the harness. Keep the target model and settings fixed if the question is harness behavior. If the model also changes, report the result as a separate benchmark rather than attributing the difference to the skill.

For distribution, publish the target packet and skill bundle to the consumer, while keeping the rubric and judge inputs in a separate evaluator location or process. A small adapter is the only harness-specific component; the suite YAML, packet exporter, validator, judge contract, and scorer remain unchanged.
