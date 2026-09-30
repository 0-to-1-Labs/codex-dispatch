# codex-dispatch

Route a prompt to **OpenAI Codex (gpt-5.6 `sol` / `luna` / `terra`)** from Claude Code and get a **synthesized** answer back — like delegating to a subagent. The Claude main agent dispatches a self-contained task, Codex runs it (with real file access), and Claude digests the result into a concise synthesis with its own judgment layered on top.

## Install

```
/plugin marketplace add 0-to-1-Labs/claude-marketplace
/plugin install codex-dispatch@0-to-1-labs
```

Requires the [`codex`](https://github.com/openai/codex) CLI installed and authenticated:

```
codex login
```

## Usage

```
/codex <prompt>                      # defaults to gpt-5.6-sol, workspace-write
/codex luna <prompt>                 # pick a variant
/codex terra <prompt>                # deepest reasoning
/codex ro <prompt>                   # read-only / advisory — Codex can inspect but not edit files
/codex ro terra <prompt>             # modifiers combine, in any order
```

### Variants

| Variant | Model id          | Use for                                   |
|---------|-------------------|-------------------------------------------|
| `sol`   | `gpt-5.6-sol`     | Fast default driver                       |
| `luna`  | `gpt-5.6-luna`    | Balanced                                  |
| `terra` | `gpt-5.6-terra`   | Deepest reasoning — hard bugs, architecture |

### Modes

- **Default (workspace-write):** Codex runs in your current directory and can read *and modify* files — a real worker, not just an oracle.
- **`ro` / `read-only`:** Codex inspects files but only returns advice. Nothing is modified.

## How it works

1. `/codex` (or the `codex-dispatch` skill, invoked autonomously) parses the variant and mode.
2. `skills/codex-dispatch/dispatch.sh` runs `codex exec` non-interactively (`approval_policy=never`, so it never hangs), streaming the trace and writing two artifacts to the session scratchpad:
   - the clean final message (`-o`)
   - the full event log (reasoning + tool calls + output)
3. The Claude main agent reads the final message, synthesizes it in its own words, flags anything questionable, lists any files Codex changed, and hands you the raw-log path.

## Configuration

The helper honors these env vars:

- `CODEX_DISPATCH_DIR` — where artifacts are written (default: `$TMPDIR/codex-dispatch`)
- `CODEX_SANDBOX` — `workspace-write` (default), `read-only`, or `danger-full-access`

If OpenAI renames a variant, edit the `case` map in `skills/codex-dispatch/dispatch.sh`.
