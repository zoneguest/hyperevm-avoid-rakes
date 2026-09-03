#!/usr/bin/env python3
"""Score paired HyperEVM skill eval judgments.

Input JSON shape:
{
  "judgments": [
    {"condition": "with_skill"|"baseline", "replicate": 1,
     "case_id": "...", "score": 0|1|2, "critical_failure": false}
  ]
}

The script deliberately does not call a model. It only aggregates already-judged
records, making the uplift calculation reproducible and auditable.
"""

import argparse
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def load_cases(path: Path):
    try:
        import yaml  # type: ignore
    except ImportError as exc:
        raise SystemExit("PyYAML is required to read the eval YAML") from exc
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return {item["id"]: item for item in data["evals"]}


def mean(values):
    return statistics.mean(values) if values else 0.0


def population_sd(values):
    return statistics.pstdev(values) if len(values) > 1 else 0.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("judgments", type=Path)
    parser.add_argument("--cases", type=Path, required=True)
    args = parser.parse_args()

    cases = load_cases(args.cases)
    payload = json.loads(args.judgments.read_text(encoding="utf-8"))
    if isinstance(payload, list) and payload and "with_skill_score" in payload[0]:
        judgments = []
        for row in payload:
            judgments.extend([
                {
                    "condition": "with_skill",
                    "case_id": row.get("case_id"),
                    "score": row.get("with_skill_score"),
                    "critical_failure": bool(row.get("with_skill_fail_triggers")),
                },
                {
                    "condition": "baseline",
                    "case_id": row.get("case_id"),
                    "score": row.get("baseline_score"),
                    "critical_failure": bool(row.get("baseline_fail_triggers")),
                },
            ])
    else:
        judgments = payload if isinstance(payload, list) else payload.get("judgments", [])
    if not judgments:
        raise SystemExit("No judgments found")

    by_condition = defaultdict(list)
    by_pair = defaultdict(dict)
    seen = defaultdict(set)
    invalid = []
    for row in judgments:
        condition = row.get("condition")
        case_id = row.get("case_id")
        score = row.get("score")
        replicate = row.get("replicate", 1)
        if condition not in {"with_skill", "baseline"} or case_id not in cases or score not in {0, 1, 2} or not isinstance(replicate, int):
            invalid.append(row)
            continue
        if (replicate, case_id) in seen[condition]:
            invalid.append({"reason": "duplicate case-condition pair", "row": row})
            continue
        if row.get("critical_failure") and score != 0:
            invalid.append({"reason": "critical failure must score zero", "row": row})
            continue
        weight = float(cases[case_id].get("weight", 1))
        fail_triggers = row.get("fail_triggers", [])
        if fail_triggers and score != 0:
            invalid.append({"reason": "fail trigger must score zero", "row": row})
            continue
        seen[condition].add((replicate, case_id))
        by_condition[condition].append((case_id, int(score), weight, replicate))
        by_pair[(replicate, case_id)][condition] = int(score)

    if invalid:
        raise SystemExit(f"Invalid judgment rows: {len(invalid)}")

    replicates = sorted({replicate for condition in seen.values() for replicate, _ in condition})
    missing = []
    for replicate in replicates:
        for case_id in cases:
            for condition in ("with_skill", "baseline"):
                if (replicate, case_id) not in seen[condition]:
                    missing.append({"replicate": replicate, "case_id": case_id, "condition": condition})
    if missing:
        raise SystemExit(f"Incomplete paired coverage: {len(missing)} missing rows")

    summary = {}
    for condition, rows in by_condition.items():
        total_weight = sum(weight for _, _, weight, _ in rows)
        weighted_score = sum(score * weight for _, score, weight, _ in rows)
        normalized = weighted_score / (2 * total_weight) if total_weight else 0.0
        critical_rows = [row for row in rows if cases[row[0]].get("critical")]
        critical_pass = sum(score == 2 for _, score, _, _ in critical_rows)
        summary[condition] = {
            "judgment_count": len(rows),
            "weighted_normalized_score": round(normalized, 4),
            "weighted_score_percent": round(normalized * 100, 2),
            "critical_pass_rate": round(critical_pass / len(critical_rows), 4) if critical_rows else None,
            "score_mean": round(mean([score for _, score, _, _ in rows]), 4),
            "score_population_sd": round(population_sd([score for _, score, _, _ in rows]), 4),
        }

    deltas = []
    per_case = defaultdict(lambda: {"with_skill": [], "baseline": []})
    for (_, case_id), values in by_pair.items():
        if "with_skill" in values and "baseline" in values:
            deltas.append(values["with_skill"] - values["baseline"])
            per_case[case_id]["with_skill"].append(values["with_skill"])
            per_case[case_id]["baseline"].append(values["baseline"])

    uplift = None
    if "with_skill" in summary and "baseline" in summary:
        uplift = round((summary["with_skill"]["weighted_normalized_score"] - summary["baseline"]["weighted_normalized_score"]) * 100, 2)

    rake_deltas = []
    for case_id, values in sorted(per_case.items()):
        w = mean(values["with_skill"])
        b = mean(values["baseline"])
        rake_deltas.append({
            "case_id": case_id,
            "rake_problem": cases[case_id].get("rake_problem"),
            "critical": bool(cases[case_id].get("critical")),
            "with_skill_mean": round(w, 4),
            "baseline_mean": round(b, 4),
            "delta": round(w - b, 4),
        })

    gate = {
        "with_skill_at_least_80_percent": bool(summary.get("with_skill", {}).get("weighted_score_percent", 0) >= 80),
        "uplift_at_least_20_points": bool(uplift is not None and uplift >= 20),
        "critical_pass_uplift_at_least_25_points": None,
        "no_large_critical_regression": all(item["delta"] >= -0.25 for item in rake_deltas if item["critical"]),
    }
    if "with_skill" in summary and "baseline" in summary and summary["with_skill"]["critical_pass_rate"] is not None and summary["baseline"]["critical_pass_rate"] is not None:
        critical_uplift = (summary["with_skill"]["critical_pass_rate"] - summary["baseline"]["critical_pass_rate"]) * 100
        gate["critical_pass_uplift_points"] = round(critical_uplift, 2)
        gate["critical_pass_uplift_at_least_25_points"] = critical_uplift >= 25

    passed = all(value is True for key, value in gate.items() if key != "critical_pass_uplift_points")
    result = {
        "summary": summary,
        "uplift_percentage_points": uplift,
        "paired_improvement_rate": round(sum(delta > 0 for delta in deltas) / len(deltas), 4) if deltas else None,
        "paired_case_count": len(deltas),
        "rake_deltas": rake_deltas,
        "success_gate": gate,
        "success_gate_passed": passed,
    }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
