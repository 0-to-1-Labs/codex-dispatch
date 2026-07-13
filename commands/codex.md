---
description: Dispatch a prompt to OpenAI Codex (gpt-5.6 sol/luna/terra) and get a synthesized answer back — like delegating to a subagent
argument-hint: "[ro] [sol|luna|terra] <prompt>"
allowed-tools: Bash, Read
---

You are dispatching a task to an external model — **OpenAI Codex, gpt-5.6 family** — and bringing back a synthesized answer, exactly like delegating to a subagent. You are the main agent orchestrating; Codex is the worker.

Raw request from the user: **$ARGUMENTS**

## Steps

1. **Parse leading modifiers, then the prompt.** Inspect the first one or two whitespace-delimited tokens of the request. In any order:
   - A token that is `ro` or `read-only` sets **advisory-only mode** (Codex gets a read-only sandbox — it can inspect files but cannot modify them).
   - A token that is `sol`, `luna`, or `terra` sets the model variant.
   - Everything after the recognized modifier token(s) is the prompt.
   - Defaults if a modifier is absent: variant `sol`, and **workspace-write** (Codex may edit files).

   Variants:
   - `sol` — fast / default driver
   - `luna` — balanced
   - `terra` — deepest reasoning (use for hard analysis, thorny bugs, architecture)

2. **Dispatch.** Run the helper, pointing its output dir at your session scratchpad so artifacts stay out of the user's repo. Set `CODEX_SANDBOX=read-only` **only** when `ro`/`read-only` was requested; otherwise omit it (defaults to workspace-write):

   ```
   [CODEX_SANDBOX=read-only] CODEX_DISPATCH_DIR="<your-scratchpad-dir>" "${CLAUDE_PLUGIN_ROOT}/skills/codex-dispatch/dispatch.sh" <variant> "<prompt>"
   ```

   - Run it from the user's current working directory. In the default (write) mode Codex can read and modify real files — treat it as capable of doing actual work, not just answering. In `ro` mode it can inspect files but only returns advice.
   - Pass a rich prompt: include any context Codex needs (it does not see this conversation). If the task references specific files, name them.
   - This call **blocks** until Codex finishes — hard prompts can take a while. Let it run.

3. **Collect.** From the helper's stderr, note `CODEX_FINAL_MSG` (Codex's clean final answer) and `CODEX_RAW_LOG` (full trace). `Read` the final message; skim the raw log only if you need the reasoning/tool detail.

4. **Synthesize and report back.** Reply to the user with:
   - A tight synthesis of Codex's answer **in your own words** (3–8 bullets or a compact paragraph) — do not paste its output verbatim.
   - Your own take: flag anything you disagree with, that looks wrong, or that needs verification.
   - If Codex modified any files, list them explicitly.
   - The `CODEX_RAW_LOG` path for full detail.

If the helper exits non-zero, show the user the tail of the raw log and the exit status instead of a synthesis.
