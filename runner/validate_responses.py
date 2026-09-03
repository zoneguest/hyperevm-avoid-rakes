#!/usr/bin/env python3
"""Validate target JSONL coverage against the rubric-free prompt packet."""

import argparse
import json
from pathlib import Path


def expected_ids(packet_path: Path):
    packet = json.loads(packet_path.read_text(encoding="utf-8"))
    return [item["case_id"] for item in packet["cases"]]


def response_ids(response_path: Path):
    ids = []
    for line_number, line in enumerate(response_path.read_text(encoding="utf-8").splitlines(), start=1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{response_path}:{line_number}: invalid JSON: {exc}") from exc
        if set(row) != {"case_id", "answer"}:
            raise SystemExit(f"{response_path}:{line_number}: expected exactly case_id and answer")
        if not isinstance(row["case_id"], str) or not isinstance(row["answer"], str) or not row["answer"].strip():
            raise SystemExit(f"{response_path}:{line_number}: case_id and non-empty answer are required")
        ids.append(row["case_id"])
    return ids


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--packet", type=Path, required=True)
    parser.add_argument("responses", type=Path, nargs="+")
    args = parser.parse_args()

    expected = expected_ids(args.packet)
    if len(expected) != len(set(expected)):
        raise SystemExit("Prompt packet contains duplicate case IDs")
    for response in args.responses:
        actual = response_ids(response)
        if actual != expected:
            raise SystemExit(f"{response}: coverage/order mismatch (expected {len(expected)} cases, got {len(actual)})")
    print(f"Validated {len(expected)} response records across {len(args.responses)} files")


if __name__ == "__main__":
    main()
