---
name: codex-dispatch
description: Dispatch a prompt to OpenAI Codex (gpt-5.6 sol/luna/terra) and get a synthesized answer back, like delegating to a subagent. Use when the user wants a second opinion from Codex/GPT, a cross-model check, or to offload a self-contained analysis or coding task to Codex. Also triggered by the /codex slash command.
---

# codex-dispatch

Route a self-contained task to an external model — **OpenAI Codex, gpt-5.6 family** — and bring back a synthesized answer. Codex acts as a subagent-style worker; you (the main agent) orchestrate and digest the result. Codex does **not** see this conversation, so every dispatch must be self-contained.

## When to use

- The user explicitly asks for a Codex / GPT-5.6 opinion or cross-model check.
- A task is well-scoped and benefits from a different model's perspective (thorny bug, architecture review, alternative implementation).
- You want to offload a chunk of self-contained work while you continue orchestrating.

## Model variants

Invoked as `gpt-5.6-<variant>`:

- `sol` — fast, the default driver
- `luna` — balanced
- `terra` — deepest reasoning; use for hard analysis and architecture

## How to dispatch

Use the helper script — do not hand-roll the `codex exec` invocation:

```
CODEX_DISPATCH_DIR="<session-scratchpad>" \
  "${CLAUDE_PLUGIN_ROOT}/skills/codex-dispatch/dispatch.sh" <variant> "<self-contained prompt>"
```

- Point `CODEX_DISPATCH_DIR` at your session scratchpad so the raw log and final-message files stay out of the user's repo.
- Run from the user's cwd. By default Codex runs with the **workspace-write** sandbox (reads and edits files; no network/outside-workspace writes). Set `CODEX_SANDBOX=read-only` for a pure advisory pass, or `CODEX_SANDBOX=danger-full-access` only when explicitly needed.
- The call blocks until Codex finishes and streams its trace to the terminal.

The helper prints these paths on stderr:

- `CODEX_FINAL_MSG=<path>` — Codex's clean final message (read this)
- `CODEX_RAW_LOG=<path>` — full event trace: reasoning, tool calls, output (skim as needed)
- `CODEX_EXIT=<n>` — exit status

## Reporting back

1. `Read` `CODEX_FINAL_MSG`.
2. Synthesize it **in your own words** — tight bullets or a compact paragraph, not a verbatim paste.
3. Add your own judgment: flag disagreements, likely errors, or claims needing verification.
4. List any files Codex modified.
5. Give the user the `CODEX_RAW_LOG` path for full detail.

On non-zero exit, surface the tail of the raw log and the exit status instead of a synthesis.

## Notes

- Model ids follow `gpt-5.6-{sol,luna,terra}`; the default in `~/.codex/config.toml` is `gpt-5.6-sol`. If OpenAI renames a variant, edit the `case` map in `dispatch.sh`.
- Requires the `codex` CLI installed and authenticated (`codex login`).
