#!/usr/bin/env bash
set -euo pipefail

# Harness-neutral reference runner for the HyperEVM capability-uplift eval.
# It uses an OpenAI-compatible chat-completions endpoint for the target and
# judge. Other harnesses can implement the same response contract and reuse
# export_prompts.py, validate_responses.py, score.py, and judge.md.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
EVAL_FILE="$SKILL_DIR/evals/hyperevm-precompiles.yaml"
JUDGE_PROMPT_FILE="$SCRIPT_DIR/judge.md"

MODEL="${EVAL_MODEL:-}"
JUDGE_MODEL="${EVAL_JUDGE_MODEL:-}"
API_URL="${API_URL:-${EVAL_API_URL:-}}"
JUDGE_API_URL="${JUDGE_API_URL:-${EVAL_JUDGE_API_URL:-}}"
TARGET_KEY_ENV="${EVAL_API_KEY_ENV:-OPENAI_API_KEY}"
JUDGE_KEY_ENV="${EVAL_JUDGE_API_KEY_ENV:-OPENAI_API_KEY}"
REPLICATES="${EVAL_REPLICATES:-1}"
RUN_DIR="${EVAL_RUN_DIR:-}"
TEMPERATURE="${EVAL_TEMPERATURE:-0}"
TOKEN_PARAMETER="${EVAL_TOKEN_PARAMETER:-max_tokens}"
MAX_OUTPUT_TOKENS="${EVAL_MAX_OUTPUT_TOKENS:-1200}"
REQUEST_TIMEOUT="${EVAL_REQUEST_TIMEOUT:-180}"
CONNECT_TIMEOUT="${EVAL_CONNECT_TIMEOUT:-20}"
FAIL_ON_GATE=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./runner/run.sh --model MODEL [options]

Runs every case in baseline and with_skill conditions, judges both responses,
and writes a scored run directory. The target and judge use an
OpenAI-compatible chat-completions endpoint; configure any provider or proxy
with --api-url/--judge-api-url.

Required:
  --model NAME                 Target model name sent to the target endpoint
  --api-url URL                Target chat-completions URL

Optional:
  --judge NAME                 Judge model (defaults to --model)
  --judge-api-url URL          Judge URL (defaults to --api-url)
  --api-key-env NAME           Env var containing target API key (default: OPENAI_API_KEY)
  --judge-api-key-env NAME     Env var containing judge API key (default: OPENAI_API_KEY)
  --cases PATH                 Eval YAML (default: evals/hyperevm-precompiles.yaml)
  --replicates N               Paired replicates (default: 1; use >=3 for a stable claim)
  --run-dir PATH               Output directory (default: results/run-TIMESTAMP)
  --temperature NUMBER         Request temperature (default: 0)
  --token-parameter NAME       max_tokens or max_completion_tokens (default: max_tokens)
  --max-output-tokens N        Output token limit (default: 1200)
  --timeout SECONDS            Per-request timeout (default: 180)
  --connect-timeout SECONDS    Connection timeout (default: 20)
  --fail-on-gate               Exit 2 when the pre-registered gate fails
  --dry-run                    Export inputs and print the planned run only
  -h, --help                   Show this help

Environment alternatives use the EVAL_* names shown above. API keys are read
from the environment and are never written to the manifest.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_arg() {
  [[ $# -ge 2 && -n "${2:-}" ]] || die "$1 requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      require_arg "$1" "${2:-}"
      MODEL="$2"
      shift 2
      ;;
    --judge)
      require_arg "$1" "${2:-}"
      JUDGE_MODEL="$2"
      shift 2
      ;;
    --api-url)
      require_arg "$1" "${2:-}"
      API_URL="$2"
      shift 2
      ;;
    --judge-api-url)
      require_arg "$1" "${2:-}"
      JUDGE_API_URL="$2"
      shift 2
      ;;
    --api-key-env)
      require_arg "$1" "${2:-}"
      TARGET_KEY_ENV="$2"
      shift 2
      ;;
    --judge-api-key-env)
      require_arg "$1" "${2:-}"
      JUDGE_KEY_ENV="$2"
      shift 2
      ;;
    --cases)
      require_arg "$1" "${2:-}"
      EVAL_FILE="$2"
      shift 2
      ;;
    --replicates)
      require_arg "$1" "${2:-}"
      REPLICATES="$2"
      shift 2
      ;;
    --run-dir)
      require_arg "$1" "${2:-}"
      RUN_DIR="$2"
      shift 2
      ;;
    --temperature)
      require_arg "$1" "${2:-}"
      TEMPERATURE="$2"
      shift 2
      ;;
    --token-parameter)
      require_arg "$1" "${2:-}"
      TOKEN_PARAMETER="$2"
      shift 2
      ;;
    --max-output-tokens)
      require_arg "$1" "${2:-}"
      MAX_OUTPUT_TOKENS="$2"
      shift 2
      ;;
    --timeout)
      require_arg "$1" "${2:-}"
      REQUEST_TIMEOUT="$2"
      shift 2
      ;;
    --connect-timeout)
      require_arg "$1" "${2:-}"
      CONNECT_TIMEOUT="$2"
      shift 2
      ;;
    --fail-on-gate)
      FAIL_ON_GATE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac
done

[[ -n "$MODEL" ]] || die "--model is required"
[[ -n "$JUDGE_MODEL" ]] || JUDGE_MODEL="$MODEL"
[[ -n "$JUDGE_API_URL" ]] || JUDGE_API_URL="$API_URL"
if [[ "$DRY_RUN" != true ]]; then
  [[ -n "$API_URL" ]] || die "--api-url is required"
  [[ -n "$JUDGE_API_URL" ]] || die "--judge-api-url or --api-url is required"
fi
[[ "$REPLICATES" =~ ^[1-9][0-9]*$ ]] || die "--replicates must be a positive integer"
[[ "$MAX_OUTPUT_TOKENS" =~ ^[1-9][0-9]*$ ]] || die "--max-output-tokens must be a positive integer"
[[ "$REQUEST_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "--timeout must be a positive integer"
[[ "$CONNECT_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "--connect-timeout must be a positive integer"
[[ "$TOKEN_PARAMETER" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "--token-parameter must be a JSON field name"
[[ "$TEMPERATURE" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--temperature must be a non-negative number"

for command_name in curl jq perl python3; do
  command -v "$command_name" >/dev/null 2>&1 || die "Missing dependency: $command_name"
done
python3 -c 'import yaml' >/dev/null 2>&1 || die "PyYAML is required; install it for python3"

if [[ -z "$RUN_DIR" ]]; then
  RUN_DIR="$SKILL_DIR/results/run-$(date +%Y%m%d-%H%M%S)"
fi
if [[ -e "$RUN_DIR" ]]; then
  [[ -d "$RUN_DIR" ]] || die "Run path exists and is not a directory: $RUN_DIR"
  [[ -z "$(find "$RUN_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die "Run directory is not empty: $RUN_DIR"
else
  mkdir -p "$RUN_DIR"
fi

CASE_FILE="$(mktemp)"
trap 'rm -f "$CASE_FILE"' EXIT

python3 "$SCRIPT_DIR/export_prompts.py" "$EVAL_FILE" "$RUN_DIR/prompts.json"

python3 - "$EVAL_FILE" "$SKILL_DIR" > "$CASE_FILE" <<'PY'
import json
import sys
from pathlib import Path

import yaml

eval_path = Path(sys.argv[1]).resolve()
skill_dir = Path(sys.argv[2]).resolve()
data = yaml.safe_load(eval_path.read_text(encoding="utf-8")) or {}
cases = data.get("evals")
if not isinstance(cases, list) or not cases:
    raise SystemExit("Eval YAML has no evals")

out = []
ids = set()
for case in cases:
    case_id = case.get("id")
    if not isinstance(case_id, str) or not case_id:
        raise SystemExit(f"Invalid case id: {case!r}")
    if case_id in ids:
        raise SystemExit(f"Duplicate case id: {case_id}")
    ids.add(case_id)
    refs = case.get("reference_files", []) or []
    if not isinstance(refs, list):
        raise SystemExit(f"reference_files must be a list: {case_id}")
    for ref in refs:
        path = (skill_dir / ref).resolve()
        try:
            path.relative_to(skill_dir)
        except ValueError:
            raise SystemExit(f"Reference escapes skill directory: {case_id}: {ref}")
        if not path.is_file():
            raise SystemExit(f"Missing reference for {case_id}: {ref}")
    out.append({
        "id": case_id,
        "prompt": case.get("prompt", ""),
        "expected_facts": case.get("expected_facts", []) or [],
        "fail_if": case.get("fail_if", []) or [],
        "critical": bool(case.get("critical", False)),
        "reference_files": refs,
    })

json.dump({"source_policy": data.get("source_policy", ""), "cases": out}, sys.stdout, ensure_ascii=False)
PY

CASE_COUNT="$(jq '.cases | length' "$CASE_FILE")"
SOURCE_POLICY="$(jq -r '.source_policy // ""' "$CASE_FILE")"
COMMON_SYSTEM="${EVAL_TARGET_SYSTEM:-You are a helpful AI assistant advising a protocol team. Answer the public case precisely and concisely. Return only answer text, not JSON, markdown fences, or evaluation commentary. Keep the answer under 180 words. Do not browse the web.}"
JUDGE_SYSTEM="$(<"$JUDGE_PROMPT_FILE")"

read_env() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Invalid environment variable name: $name"
  printf '%s' "${!name:-}"
}

TARGET_API_KEY="$(read_env "$TARGET_KEY_ENV")"
JUDGE_API_KEY="$(read_env "$JUDGE_KEY_ENV")"
[[ -n "$JUDGE_API_KEY" ]] || JUDGE_API_KEY="$TARGET_API_KEY"

if [[ "$DRY_RUN" == true ]]; then
  jq -n \
    --arg suite "hyperevm-avoid-rakes" \
    --arg model "$MODEL" \
    --arg judge "$JUDGE_MODEL" \
    --arg run_dir "$RUN_DIR" \
    --argjson replicates "$REPLICATES" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{suite: $suite, model: $model, judge_model: $judge, replicates: $replicates, run_dir: $run_dir, status: "dry-run", created_at: $timestamp}' \
    > "$RUN_DIR/manifest.json"
  echo "Dry run: $CASE_COUNT cases x $REPLICATES paired replicate(s)"
  echo "Inputs written to: $RUN_DIR"
  exit 0
fi

jq -n \
  --arg suite "hyperevm-avoid-rakes" \
  --arg runner "runner/run.sh" \
  --arg model "$MODEL" \
  --arg judge "$JUDGE_MODEL" \
  --arg api_url "$API_URL" \
  --arg judge_api_url "$JUDGE_API_URL" \
  --arg target_key_env "$TARGET_KEY_ENV" \
  --arg judge_key_env "$JUDGE_KEY_ENV" \
  --arg token_parameter "$TOKEN_PARAMETER" \
  --arg temperature "$TEMPERATURE" \
  --arg max_output_tokens "$MAX_OUTPUT_TOKENS" \
  --argjson replicates "$REPLICATES" \
  --argjson case_count "$CASE_COUNT" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{suite: $suite, runner: $runner, model: $model, judge_model: $judge, api_url: $api_url, judge_api_url: $judge_api_url, api_key_env: {target: $target_key_env, judge: $judge_key_env}, temperature: $temperature, token_parameter: $token_parameter, max_output_tokens: $max_output_tokens, replicates: $replicates, case_count: $case_count, status: "running", created_at: $timestamp}' \
  > "$RUN_DIR/manifest.json"

build_skill_system() {
  local case_index="$1"
  local context="$COMMON_SYSTEM"
  local ref
  context+=$'\n\n--- SKILL.md ---\n'
  context+="$(<"$SKILL_DIR/SKILL.md")"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    context+=$'\n\n--- '
    context+="$ref"
    context+=$' ---\n'
    context+="$(<"$SKILL_DIR/$ref")"
  done < <(jq -r ".cases[$case_index].reference_files[]?" "$CASE_FILE")
  printf '%s' "$context"
}

call_chat() {
  local url="$1"
  local api_key="$2"
  local model="$3"
  local system_message="$4"
  local user_message="$5"
  local payload response content venice_parameters='{}' reasoning='{}'
  local -a curl_args

  system_message="$(printf '%s' "$system_message" | sanitize_ascii)"
  user_message="$(printf '%s' "$user_message" | sanitize_ascii)"

  if [[ "$url" == *api.venice.ai* ]]; then
    venice_parameters='{"include_venice_system_prompt":false,"disable_thinking":true,"strip_thinking_response":true}'
    reasoning='{"enabled":false}'
  fi

  if [[ "$TEMPERATURE" == "" ]]; then
    payload="$(jq -n \
      --arg model "$model" \
      --arg system "$system_message" \
      --arg user "$user_message" \
      --arg token_parameter "$TOKEN_PARAMETER" \
      --argjson max_output_tokens "$MAX_OUTPUT_TOKENS" \
      --argjson venice_parameters "$venice_parameters" \
      --argjson reasoning "$reasoning" \
      '{model: $model, messages: [{role: "system", content: $system}, {role: "user", content: $user}], ($token_parameter): $max_output_tokens} + (if ($venice_parameters | length) > 0 then {venice_parameters: $venice_parameters} else {} end) + (if ($reasoning | length) > 0 then {reasoning: $reasoning} else {} end)')"
  else
    payload="$(jq -n \
      --arg model "$model" \
      --arg system "$system_message" \
      --arg user "$user_message" \
      --arg token_parameter "$TOKEN_PARAMETER" \
      --argjson temperature "$TEMPERATURE" \
      --argjson max_output_tokens "$MAX_OUTPUT_TOKENS" \
      --argjson venice_parameters "$venice_parameters" \
      --argjson reasoning "$reasoning" \
      '{model: $model, messages: [{role: "system", content: $system}, {role: "user", content: $user}], temperature: $temperature, ($token_parameter): $max_output_tokens} + (if ($venice_parameters | length) > 0 then {venice_parameters: $venice_parameters} else {} end) + (if ($reasoning | length) > 0 then {reasoning: $reasoning} else {} end)')"
  fi

  curl_args=(--silent --show-error --connect-timeout "$CONNECT_TIMEOUT" --max-time "$REQUEST_TIMEOUT" -H "Content-Type: application/json")
  if [[ -n "$api_key" ]]; then
    curl_args+=(-H "Authorization: Bearer $api_key")
  fi
  response="$(curl "${curl_args[@]}" --data "$payload" "$url")" || {
    echo "Chat request failed for model $model at $url" >&2
    return 1
  }

  if [[ "$url" == *api.venice.ai* ]] && jq -e '
    ((.choices[0].message.content? // "") == "") and
    .choices[0].finish_reason == "length"
  ' >/dev/null 2>&1 <<< "$response"; then
    payload="$(jq --arg token_parameter "$TOKEN_PARAMETER" --argjson max_output_tokens "$((MAX_OUTPUT_TOKENS * 2))" '.[$token_parameter] = $max_output_tokens' <<< "$payload")"
    response="$(curl "${curl_args[@]}" --data "$payload" "$url")" || {
      echo "Chat request failed for model $model at $url" >&2
      return 1
    }
  fi

  content="$(jq -er '
    def as_text:
      if type == "string" then .
      elif type == "array" then ([.[] | (.text? // .content? // empty) | tostring] | join(""))
      else empty
      end;
    (.choices[0].message.content? // .choices[0].text? // .content?) | as_text | select(length > 0)
  ' <<< "$response")" || {
    echo "Chat response did not contain usable text for model $model" >&2
    if jq -e . >/dev/null 2>&1 <<< "$response"; then
      jq . >&2 <<< "$response"
    else
      echo "$response" >&2
    fi
    return 1
  }
  printf '%s' "$content"
}

sanitize_ascii() {
  perl -CSDA -pe '
    s/\x{2018}|\x{2019}/'"'"'/g;
    s/\x{201C}|\x{201D}/"/g;
    s/\x{2013}|\x{2014}/-/g;
    s/\x{2026}/.../g;
    s/\x{00A0}/ /g;
    s/[^\x00-\x7F]/ /g;
  '
}

extract_json_object() {
  python3 -c '
import json
import sys

text = sys.stdin.read().strip()
decoder = json.JSONDecoder()
try:
    value = json.loads(text)
except json.JSONDecodeError:
    value = None
    for index, character in enumerate(text):
        if character != "{":
            continue
        try:
            candidate, _ = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(candidate, dict):
            value = candidate
            break
if not isinstance(value, dict):
    raise SystemExit("judge did not return a JSON object")
print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
'
}

make_judgment() {
  local condition="$1"
  local replicate="$2"
  local case_id="$3"
  local judge_json="$4"
  local score critical_failure fail_triggers expected_hits expected_misses verdict reasoning

  if ! jq -e --arg case_id "$case_id" '(.case_id == null or .case_id == $case_id)' >/dev/null <<< "$judge_json"; then
    die "Judge returned the wrong case_id for $condition/$case_id"
  fi
  score="$(jq -r 'if .score != null then .score elif .verdict == "PASS" then 2 elif .verdict == "PARTIAL" then 1 elif .verdict == "FAIL" then 0 else empty end' <<< "$judge_json")"
  [[ "$score" =~ ^[012]$ ]] || die "Judge returned no valid 0-2 score for $condition/$case_id"
  fail_triggers="$(jq -c '.fail_triggers // []' <<< "$judge_json")"
  jq -e 'type == "array"' >/dev/null <<< "$fail_triggers" || die "Judge fail_triggers is not an array for $condition/$case_id"
  critical_failure="$(jq -r 'if .critical_failure != null then .critical_failure elif ((.fail_triggers // []) | length > 0) then true else false end' <<< "$judge_json")"
  [[ "$critical_failure" == true || "$critical_failure" == false ]] || die "Judge critical_failure is not boolean for $condition/$case_id"
  expected_hits="$(jq -c '.expected_hits // []' <<< "$judge_json")"
  expected_misses="$(jq -c '.expected_misses // []' <<< "$judge_json")"
  verdict="$(jq -r '.verdict // empty' <<< "$judge_json")"
  reasoning="$(jq -r '.reasoning // empty' <<< "$judge_json")"

  jq -cn \
    --arg condition "$condition" \
    --argjson replicate "$replicate" \
    --arg case_id "$case_id" \
    --argjson score "$score" \
    --argjson critical_failure "$critical_failure" \
    --argjson fail_triggers "$fail_triggers" \
    --argjson expected_hits "$expected_hits" \
    --argjson expected_misses "$expected_misses" \
    --arg verdict "$verdict" \
    --arg reasoning "$reasoning" \
    '{condition: $condition, replicate: $replicate, case_id: $case_id, score: $score, critical_failure: $critical_failure, fail_triggers: $fail_triggers, expected_hits: $expected_hits, expected_misses: $expected_misses, verdict: $verdict, reasoning: $reasoning}'
}

run_target_case() {
  local case_index="$1"
  local condition="$2"
  local prompt system_message
  prompt="$(jq -r ".cases[$case_index].prompt" "$CASE_FILE")"
  if [[ "$condition" == "with_skill" ]]; then
    system_message="$(build_skill_system "$case_index")"
  else
    system_message="$COMMON_SYSTEM"
  fi
  call_chat "$API_URL" "$TARGET_API_KEY" "$MODEL" "$system_message" "$prompt"
}

run_judge_case() {
  local case_index="$1"
  local condition="$2"
  local answer="$3"
  local prompt expected_facts fail_if case_id judge_input judge_raw judge_json
  case_id="$(jq -r ".cases[$case_index].id" "$CASE_FILE")"
  prompt="$(jq -r ".cases[$case_index].prompt" "$CASE_FILE")"
  expected_facts="$(jq -r ".cases[$case_index].expected_facts[]? | \"- \" + ." "$CASE_FILE")"
  fail_if="$(jq -r ".cases[$case_index].fail_if[]? | \"- \" + ." "$CASE_FILE")"
  judge_input=$'## Case ID\n'"$case_id"$'\n\n## Source policy\n'"$SOURCE_POLICY"$'\n\n## Prompt\n'"$prompt"$'\n\n## Response\n'"$answer"$'\n\n## Expected Facts\n'"$expected_facts"$'\n\n## Fail Conditions\n'"$fail_if"
  judge_raw="$(call_chat "$JUDGE_API_URL" "$JUDGE_API_KEY" "$JUDGE_MODEL" "$JUDGE_SYSTEM" "$judge_input")"
  judge_json="$(printf '%s' "$judge_raw" | extract_json_object)" || die "Could not parse judge response for $condition/$case_id"
  make_judgment "$condition" "$CURRENT_REPLICATE" "$case_id" "$judge_json"
}

echo "╔══════════════════════════════════════════════╗"
echo "║       HyperEVM capability-uplift eval        ║"
echo "╠══════════════════════════════════════════════╣"
echo "║ Target:     $MODEL"
echo "║ Judge:      $JUDGE_MODEL"
echo "║ Cases:      $CASE_COUNT"
echo "║ Replicates: $REPLICATES"
echo "║ Run dir:    $RUN_DIR"
echo "╚══════════════════════════════════════════════╝"
echo

JUDGMENTS_JSONL="$RUN_DIR/judgments.jsonl"
: > "$JUDGMENTS_JSONL"

for CURRENT_REPLICATE in $(seq 1 "$REPLICATES"); do
  REPLICATE_DIR="$RUN_DIR/replicate-$CURRENT_REPLICATE"
  mkdir -p "$REPLICATE_DIR"
  WITH_RESPONSES="$REPLICATE_DIR/with_skill.jsonl"
  BASELINE_RESPONSES="$REPLICATE_DIR/baseline.jsonl"
  : > "$WITH_RESPONSES"
  : > "$BASELINE_RESPONSES"
  echo "━━━ replicate $CURRENT_REPLICATE/$REPLICATES ━━━"

  for ((case_index = 0; case_index < CASE_COUNT; case_index++)); do
    case_id="$(jq -r ".cases[$case_index].id" "$CASE_FILE")"
    if (( RANDOM % 2 == 0 )); then
      FIRST_CONDITION="with_skill"
      SECOND_CONDITION="baseline"
    else
      FIRST_CONDITION="baseline"
      SECOND_CONDITION="with_skill"
    fi

    response_with=""
    response_baseline=""
    for condition in "$FIRST_CONDITION" "$SECOND_CONDITION"; do
      echo -n "  [$case_id] $condition ... "
      answer="$(run_target_case "$case_index" "$condition")"
      [[ -n "${answer//[[:space:]]/}" ]] || die "Empty target answer for $condition/$case_id"
      if [[ "$condition" == "with_skill" ]]; then
        response_with="$answer"
        jq -cn --arg case_id "$case_id" --arg answer "$answer" '{case_id: $case_id, answer: $answer}' >> "$WITH_RESPONSES"
      else
        response_baseline="$answer"
        jq -cn --arg case_id "$case_id" --arg answer "$answer" '{case_id: $case_id, answer: $answer}' >> "$BASELINE_RESPONSES"
      fi
      echo "done"
    done

    for condition in with_skill baseline; do
      if [[ "$condition" == "with_skill" ]]; then
        answer="$response_with"
      else
        answer="$response_baseline"
      fi
      echo -n "  [$case_id] judge $condition ... "
      judgment="$(run_judge_case "$case_index" "$condition" "$answer")"
      printf '%s\n' "$judgment" >> "$JUDGMENTS_JSONL"
      echo "done"
    done
  done

  python3 "$SCRIPT_DIR/validate_responses.py" \
    --packet "$RUN_DIR/prompts.json" \
    "$WITH_RESPONSES" "$BASELINE_RESPONSES"
done

jq -s '.' "$JUDGMENTS_JSONL" > "$RUN_DIR/judgments.json"
python3 "$SCRIPT_DIR/score.py" \
  "$RUN_DIR/judgments.json" \
  --cases "$EVAL_FILE" \
  > "$RUN_DIR/score.json"

FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --arg finished_at "$FINISHED_AT" '.status = "completed" | .finished_at = $finished_at' \
  "$RUN_DIR/manifest.json" > "$RUN_DIR/manifest.tmp"
mv "$RUN_DIR/manifest.tmp" "$RUN_DIR/manifest.json"

echo
echo "╔══════════════════════════════════════════════╗"
echo "║              RESULTS SUMMARY                 ║"
echo "╠══════════════════════════════════════════════╣"
jq -r '"║ With skill: " + ((.summary.with_skill.weighted_score_percent // "n/a") | tostring) + "%", "║ Baseline:   " + ((.summary.baseline.weighted_score_percent // "n/a") | tostring) + "%", "║ Uplift:     " + ((.uplift_percentage_points // "n/a") | tostring) + " points", "║ Gate:       " + ((.success_gate_passed // false) | tostring)' "$RUN_DIR/score.json"
echo "╚══════════════════════════════════════════════╝"
echo "Results saved to: $RUN_DIR"

if [[ "$FAIL_ON_GATE" == true ]] && ! jq -e '.success_gate_passed == true' "$RUN_DIR/score.json" >/dev/null; then
  exit 2
fi
