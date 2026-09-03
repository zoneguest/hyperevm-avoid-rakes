#!/usr/bin/env python3
"""Export only the public prompt surface of an eval suite.

The target agent must never receive expected_facts, fail_if, rake_problem,
weights, or reference routing. Those fields are judge-only and would
contaminate the baseline condition.
"""

import argparse
import json
from pathlib import Path

import yaml


FORBIDDEN_FIELDS = {
    "expected_facts",
    "fail_if",
    "rake_problem",
    "critical",
    "weight",
    "reference_files",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("cases", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    data = yaml.safe_load(args.cases.read_text(encoding="utf-8"))
    cases = data.get("evals", [])
    if not cases:
        raise SystemExit("No eval cases found")

    public_cases = []
    for case in cases:
        if not {"id", "prompt"}.issubset(case):
            raise SystemExit(f"Case is missing id or prompt: {case!r}")
        public_cases.append({"case_id": case["id"], "prompt": case["prompt"]})

    packet = {
        "schema_version": 1,
        "cases": public_cases,
    }
    serialized = json.dumps(packet, indent=2, ensure_ascii=False)
    leaked = [field for field in FORBIDDEN_FIELDS if f'"{field}"' in serialized]
    if leaked:
        raise SystemExit(f"Blind prompt packet contains hidden fields: {leaked}")
    args.output.write_text(serialized + "\n", encoding="utf-8")
    print(f"Exported {len(public_cases)} blind prompts to {args.output}")


if __name__ == "__main__":
    main()
