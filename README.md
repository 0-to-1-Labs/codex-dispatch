# codex-dispatch

Route a prompt to **OpenAI Codex (GPT-6 `sol` / `astra` / `luna`)** from Claude Code and get a **synthesized** answer back — like delegating to a subagent. The Claude main agent dispatches a self-contained task, Codex runs it, and Claude digests the result into a concise synthesis with its own judgment layered on top.

Codex runs **read-only** unless you ask for edits. Only a typed `/codex` starts a run; Claude never dispatches on its own.

## Install

```
/plugin marketplace add 0-to-1-Labs/claude-marketplace
/plugin install codex-dispatch@0-to-1-labs
```

Requires the [`codex`](https://github.com/openai/codex) CLI installed and authenticated:

```
codex login
```

Codex CLI **0.159.1 or later** is recommended. That release added `gpt-6.1-sol` to the bundled catalog. On an older CLI, pass a model your CLI knows with `CODEX_MODEL` (see Configuration).

## Keep the plugin updated

Claude Code can update this plugin automatically. Auto-update is off by default for third-party marketplaces, so turn it on once:

1. Run `/plugin`.
2. Open the **Marketplaces** tab and select `0-to-1-labs`.
3. Choose **Enable auto-update**.

Claude Code then checks for new versions after each session start and installs them. Restart Claude Code to load an update.

To update by hand:

```
claude plugin marketplace update 0-to-1-labs
claude plugin update codex-dispatch@0-to-1-labs
```

## Usage

```
/codex <prompt>                      # gpt-6.1-sol, read-only
/codex luna <prompt>                 # pick a variant
/codex astra <prompt>                # most capable — hard bugs, architecture
/codex rw <prompt>                   # write mode — Codex may edit files in your repo
/codex rw astra <prompt>             # modifiers combine, in any order
```

### Variants

| Variant | Model id      | Use for                                                        |
|---------|---------------|----------------------------------------------------------------|
| `sol`   | `gpt-6.1-sol` | Default. Codex's own default; near-Astra quality at lower cost |
| `astra` | `gpt-6-astra` | Most capable, most expensive — hard analysis, architecture     |
| `luna`  | `gpt-6-luna`  | Fastest and cheapest — easy, well-scoped tasks                 |

### Modes

- **Default (read-only):** Codex inspects files but only returns advice. Nothing is modified.
- **`rw` / `write`:** Codex runs in your current directory and can read *and modify* files. Claude uses it only when you ask for edits. Write mode needs a git repository, so changes can be reverted. After the run Claude lists every changed file and flags edits to `CLAUDE.md`, `.claude/`, hooks, or settings.

## How it works

1. `/codex` parses the variant and mode. The skill is user-invoked only (`disable-model-invocation: true`), and its Bash grant covers the helper script alone.
2. `skills/codex-dispatch/dispatch.sh` runs `codex exec` non-interactively (`approval_policy=never`). It writes two files to the output directory (Claude's session scratchpad, else `$TMPDIR/codex-dispatch`):
   - the clean final message (`-o`)
   - the full trace (progress, tool calls, output), kept out of Claude's context
3. The Claude main agent reads the final message, synthesizes it in its own words, flags anything questionable, lists any files Codex changed, and hands you the raw-log path.

Claude treats Codex's output as untrusted text: it reports instructions found there instead of following them.

### Timeouts

Claude's Bash tool stops a foreground command after 2 minutes by default and 10 minutes at most. The skill sets the tool timeout to the maximum and passes `--timeout 540` to the helper, so a long run ends with a clean `CODEX_EXIT=124` and the log tail. The helper prints the output paths before the run starts, so they survive a kill. For longer jobs the skill can run the helper in the background.

## Configuration

`dispatch.sh` takes flags; each has an environment variable fallback:

| Flag                   | Env var              | Meaning                                                          |
|------------------------|----------------------|------------------------------------------------------------------|
| `--rw`                 | `CODEX_SANDBOX=workspace-write` | Let Codex edit files. Default sandbox is `read-only`. |
| `--dir <path>`         | `CODEX_DISPATCH_DIR` | Where the log and final message go (default `$TMPDIR/codex-dispatch`) |
| `--timeout <seconds>`  | `CODEX_TIMEOUT`      | Kill Codex after this long; exit 124. `0` = no limit             |
| `--model <id>`         | `CODEX_MODEL`        | Exact model id; bypasses the variant map                         |
| `--effort <level>`     | `CODEX_REASONING`    | `model_reasoning_effort`: `low`, `medium`, `high`, `xhigh`, `max`, `ultra` |
| `--prompt-file <path>` |                      | Read the prompt from a file. Stdin (heredoc) also works          |

`danger-full-access` (no sandbox, no approvals) has no flag and is never suggested to Claude. To use it you must set both `CODEX_SANDBOX=danger-full-access` and `CODEX_DISPATCH_ALLOW_FULL_ACCESS=1` yourself.

Logs can contain the contents of files Codex read. They are written with mode `600` and are not deleted; clear the output directory when you are done.

If OpenAI renames a variant, edit the `case` map in `skills/codex-dispatch/dispatch.sh`, or set `CODEX_MODEL` until the plugin is updated.

## Changes in 2.0.0

Breaking changes for existing users:

- **Models moved to the GPT-6 family.** `sol` → `gpt-6.1-sol`, new `astra` → `gpt-6-astra`, `luna` → `gpt-6-luna`. `terra` was removed and is now rejected as an unknown variant; `astra` is the deepest tier. The old descriptions were inverted (`sol` was the flagship, `luna` the cheapest); they now match OpenAI's catalog.
- **Default sandbox is `read-only`.** Use `rw` (or `--rw`) for edits. The old `ro` modifier is now the default and is no longer needed.
- **`danger-full-access` is gated** behind `CODEX_DISPATCH_ALLOW_FULL_ACCESS=1`.
- **`/codex` is the only entry point.** The separate `codex-dispatch` skill entry is gone; Claude no longer triggers a dispatch on its own.
- **Flags replace bare env vars** in the documented invocation (`--dir`, `--rw`, `--timeout`, `--model`, `--effort`). The env vars still work as fallbacks.
- The prompt goes through a quoted heredoc or `--prompt-file`, never inside double quotes on the command line. `--` now precedes the prompt, so a prompt that starts with `-` works.
- The trace no longer streams into Claude's context; it goes to the log. On failure the helper prints the last 30 lines.
- Preflight checks: `codex` on PATH, logged in, writable output directory, git repository for write mode. Output file names include the PID, so concurrent runs do not collide.
