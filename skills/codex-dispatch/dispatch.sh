#!/usr/bin/env bash
# codex-dispatch: route a prompt to an OpenAI Codex GPT-6 variant and capture output.
#
# Usage:  dispatch.sh [options] <sol|astra|luna> [prompt...]
#    or:  dispatch.sh [options] <sol|astra|luna> <<'CODEX_PROMPT'
#         <prompt, any characters, many lines>
#         CODEX_PROMPT
#    or:  dispatch.sh [options] --prompt-file <path> <sol|astra|luna>
#
# Variants (model ids from the Codex catalog):
#   sol    gpt-6.1-sol   Codex's default; near-Astra quality at lower cost. Default here.
#   astra  gpt-6-astra   most capable and most expensive; hard analysis, architecture
#   luna   gpt-6-luna    fastest and cheapest; easy, well-scoped tasks
#
# Options (each has an env var fallback; the flag wins):
#   --rw                  workspace-write sandbox: Codex may edit files under $PWD
#                         (CODEX_SANDBOX=workspace-write). Default is read-only.
#   --dir <path>          where to write the log and final message
#                         (CODEX_DISPATCH_DIR; default: $TMPDIR/codex-dispatch)
#   --timeout <seconds>   kill Codex after this many seconds (CODEX_TIMEOUT; 0 = no limit)
#   --model <id>          exact model id; bypasses the variant map (CODEX_MODEL)
#   --effort <level>      model_reasoning_effort: low|medium|high|xhigh|max|ultra (CODEX_REASONING)
#   --prompt-file <path>  read the prompt from this file
#   --                    end of options
#
# danger-full-access has no flag. It runs only when the user sets both
# CODEX_SANDBOX=danger-full-access and CODEX_DISPATCH_ALLOW_FULL_ACCESS=1.
#
# On stderr it prints machine-readable lines the caller can grep. The two path
# lines print BEFORE the blocking call, so they survive a kill:
#   CODEX_RAW_LOG=<path>    full trace (progress, tool calls, output)
#   CODEX_FINAL_MSG=<path>  Codex's clean final message only
#   CODEX_EXIT=<n>          codex exit status (124 = timeout, 127 = codex not found)
set -uo pipefail
umask 077

usage() {
  echo "Usage: dispatch.sh [--rw] [--dir <path>] [--timeout <s>] [--model <id>] [--effort <level>] [--prompt-file <path>] <sol|astra|luna> [prompt...]" >&2
  echo "   or: dispatch.sh [options] <sol|astra|luna> <<'CODEX_PROMPT' ... CODEX_PROMPT" >&2
  exit 2
}
die() { echo "error: $1" >&2; exit "${2:-2}"; }

rw=0
out_dir="${CODEX_DISPATCH_DIR:-${TMPDIR:-/tmp}/codex-dispatch}"
timeout="${CODEX_TIMEOUT:-0}"
model="${CODEX_MODEL:-}"
effort="${CODEX_REASONING:-}"
prompt_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --rw) rw=1; shift ;;
    --dir) [ $# -ge 2 ] || usage; out_dir="$2"; shift 2 ;;
    --timeout) [ $# -ge 2 ] || usage; timeout="$2"; shift 2 ;;
    --model) [ $# -ge 2 ] || usage; model="$2"; shift 2 ;;
    --effort) [ $# -ge 2 ] || usage; effort="$2"; shift 2 ;;
    --prompt-file) [ $# -ge 2 ] || usage; prompt_file="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) break ;;
  esac
done

# Variant: required unless --model is set, in which case it is optional.
variant=""
case "${1:-}" in
  sol|astra|luna) variant="$1"; shift ;;
esac
[ "${1:-}" = "--" ] && shift
if [ -z "$model" ]; then
  [ -n "$variant" ] || { [ $# -gt 0 ] && die "unknown variant '$1' (expected sol|astra|luna)"; usage; }
  case "$variant" in
    sol)   model="gpt-6.1-sol" ;;
    astra) model="gpt-6-astra" ;;
    luna)  model="gpt-6-luna" ;;
  esac
fi
label="${variant:-custom}"

# Prompt from remaining args, else from --prompt-file, else from stdin.
if [ $# -gt 0 ]; then
  prompt="$*"
elif [ -n "$prompt_file" ]; then
  [ -r "$prompt_file" ] || die "cannot read prompt file '$prompt_file'"
  prompt="$(cat "$prompt_file")"
elif [ ! -t 0 ]; then
  prompt="$(cat)"
else
  usage
fi
[ -n "${prompt//[[:space:]]/}" ] || die "empty prompt"

case "$timeout" in
  ''|*[!0-9]*) die "--timeout must be a whole number of seconds (got '$timeout')" ;;
esac
if [ -n "$effort" ]; then
  case "$effort" in
    low|medium|high|xhigh|max|ultra) ;;
    *) die "--effort must be one of low|medium|high|xhigh|max|ultra (got '$effort')" ;;
  esac
fi

# Sandbox: read-only unless --rw. danger-full-access needs a user-set opt-in.
sandbox="${CODEX_SANDBOX:-read-only}"
[ "$rw" = 1 ] && sandbox="workspace-write"
case "$sandbox" in
  read-only|workspace-write) ;;
  danger-full-access)
    [ "${CODEX_DISPATCH_ALLOW_FULL_ACCESS:-}" = 1 ] \
      || die "danger-full-access is disabled. The user must set CODEX_DISPATCH_ALLOW_FULL_ACCESS=1 to allow it."
    echo "[codex-dispatch] WARNING: danger-full-access: no sandbox, no approvals, network on. Codex can touch anything this user can." >&2 ;;
  *) die "unknown CODEX_SANDBOX '$sandbox' (expected read-only|workspace-write)" ;;
esac

# Preflight: codex present and logged in.
command -v codex >/dev/null 2>&1 || die "codex CLI not found on PATH; install it and run 'codex login'" 127
codex login status >/dev/null 2>&1 || die "codex is not logged in; run 'codex login'"

# Outside a git repo: allow read-only runs; refuse writes (nothing to revert to).
extra=()
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$sandbox" = read-only ]; then
    extra+=(--skip-git-repo-check)
  else
    die "$PWD is not inside a git repository; write mode is refused because edits could not be reverted"
  fi
fi
if [ -n "$effort" ]; then
  extra+=(-c "model_reasoning_effort=$effort")
fi

mkdir -p "$out_dir" || die "cannot create output dir '$out_dir'"
[ -w "$out_dir" ] || die "output dir '$out_dir' is not writable"
[ -O "$out_dir" ] || die "output dir '$out_dir' is owned by another user; set --dir to a directory you own"
ts="$(date +%Y%m%d-%H%M%S)"
base="$out_dir/codex-${label}-${ts}-$$"
raw="$base.log"
final="$base.md"
marker="$base.timeout"

echo "[codex-dispatch] model=$model sandbox=$sandbox cwd=$PWD timeout=${timeout}s effort=${effort:-default}" >&2
[ "$sandbox" = read-only ] || echo "[codex-dispatch] WRITE MODE: Codex may edit files under $PWD" >&2
echo "CODEX_RAW_LOG=$raw" >&2
echo "CODEX_FINAL_MSG=$final" >&2
echo "[codex-dispatch] running codex exec; this blocks until it finishes (trace goes to the log)..." >&2

: > "$raw" || die "cannot write '$raw'"
codex exec \
  -m "$model" \
  -s "$sandbox" \
  -c approval_policy=never \
  -C "$PWD" \
  -o "$final" \
  ${extra[@]+"${extra[@]}"} \
  -- "$prompt" >"$raw" 2>&1 &
codex_pid=$!

watchdog=""
if [ "$timeout" -gt 0 ]; then
  (
    trap 'kill "$s" 2>/dev/null; exit 0' TERM INT HUP
    sleep "$timeout" & s=$!
    wait "$s"
    : > "$marker"
    kill -TERM "$codex_pid" 2>/dev/null
  ) &
  watchdog=$!
fi
# Forward a kill from the caller (for example the Bash tool timeout) to Codex.
trap 'kill -TERM "$codex_pid" 2>/dev/null; [ -n "$watchdog" ] && kill -TERM "$watchdog" 2>/dev/null' TERM INT HUP

wait "$codex_pid"; status=$?
while [ "$status" -gt 128 ] && kill -0 "$codex_pid" 2>/dev/null; do
  wait "$codex_pid"; status=$?
done
trap - TERM INT HUP
if [ -n "$watchdog" ]; then
  kill -TERM "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
fi
if [ -e "$marker" ]; then
  rm -f "$marker"
  status=124
  echo "[codex-dispatch] timed out after ${timeout}s; Codex was killed. Partial trace is in the log." >&2
fi

if [ "$status" -ne 0 ]; then
  echo "[codex-dispatch] codex exited $status; last lines of the log:" >&2
  tail -n 30 "$raw" >&2
fi
echo "CODEX_EXIT=$status" >&2
exit "$status"
