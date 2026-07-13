#!/usr/bin/env bash
# codex-dispatch: route a prompt to an OpenAI Codex gpt-5.6 variant and capture output.
#
# Usage:  dispatch.sh <sol|luna|terra> <prompt...>
#    or:  echo "prompt" | dispatch.sh <sol|luna|terra>
#
# Env:
#   CODEX_DISPATCH_DIR  where to write the raw log + final message (default: $TMPDIR/codex-dispatch)
#   CODEX_SANDBOX       sandbox mode (default: workspace-write; other: read-only, danger-full-access)
#
# On stderr it prints machine-readable paths the caller can grep:
#   CODEX_RAW_LOG=<path>    full event trace (reasoning + tool calls + output)
#   CODEX_FINAL_MSG=<path>  Codex's clean final message only
#   CODEX_EXIT=<n>          codex exit status
set -uo pipefail

usage() {
  echo "Usage: dispatch.sh <sol|luna|terra> <prompt...>" >&2
  echo "   or: echo 'prompt' | dispatch.sh <sol|luna|terra>" >&2
  exit 2
}

[ $# -ge 1 ] || usage

variant="$1"; shift
case "$variant" in
  sol|luna|terra) ;;
  *) echo "error: unknown variant '$variant' (expected sol|luna|terra)" >&2; exit 2 ;;
esac
model="gpt-5.6-${variant}"

# Prompt from remaining args, else from stdin.
if [ $# -gt 0 ]; then
  prompt="$*"
elif [ ! -t 0 ]; then
  prompt="$(cat)"
else
  usage
fi
[ -n "${prompt//[[:space:]]/}" ] || { echo "error: empty prompt" >&2; exit 2; }

out_dir="${CODEX_DISPATCH_DIR:-${TMPDIR:-/tmp}/codex-dispatch}"
mkdir -p "$out_dir"
ts="$(date +%Y%m%d-%H%M%S)"
raw="$out_dir/codex-${variant}-${ts}.log"
final="$out_dir/codex-${variant}-${ts}.md"
sandbox="${CODEX_SANDBOX:-workspace-write}"

echo "[codex-dispatch] model=$model sandbox=$sandbox cwd=$PWD" >&2
echo "[codex-dispatch] streaming Codex output below; this blocks until it finishes..." >&2
echo "----------------------------------------------------------------------" >&2

codex exec \
  -m "$model" \
  -s "$sandbox" \
  -c approval_policy="never" \
  -C "$PWD" \
  --skip-git-repo-check \
  -o "$final" \
  "$prompt" 2>&1 | tee "$raw"
status=${PIPESTATUS[0]}

echo "----------------------------------------------------------------------" >&2
echo "CODEX_RAW_LOG=$raw" >&2
echo "CODEX_FINAL_MSG=$final" >&2
echo "CODEX_EXIT=$status" >&2
exit "$status"
