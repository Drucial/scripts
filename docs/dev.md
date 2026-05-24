# `dev` — Kitty + Neovim + Claude Code workflow

`dev` orchestrates a kitty tab with Neovim, a shell, and a Claude Code
TUI side-by-side, automatically wiring Claude to the nvim instance over
the Claude Code IDE WebSocket protocol. Files edited from Claude appear
as diffs in nvim; `@`-mentions resolve against the same workspace;
buffers reload live when Claude edits a file.

## Architecture

Four moving pieces coordinate to make this work:

```
┌─ kitty (the terminal) ────────────────────────────────────────────┐
│                                                                   │
│  ┌─ tab ─────────────────────────────────────────────────────┐    │
│  │                                                           │    │
│  │  ┌─ nvim ────────────────────┐  ┌─ Claude Code TUI ────┐  │    │
│  │  │ coder/claudecode.nvim     │  │                      │  │    │
│  │  │  • WebSocket server       │◀─┤ claude --ide         │  │    │
│  │  │  • writes lockfile        │  │  (env: SSE_PORT)     │  │    │
│  │  │  • fs watcher (autocmds)  │  │                      │  │    │
│  │  └───────────────────────────┘  │                      │  │    │
│  │                                 │                      │  │    │
│  │  ┌─ shell ───────────────────┐  │                      │  │    │
│  │  │  $ ...                    │  │                      │  │    │
│  │  └───────────────────────────┘  └──────────────────────┘  │    │
│  │                                                           │    │
│  └───────────────────────────────────────────────────────────┘    │
│                                                                   │
│      ┌────────────────────────────────────────────────┐           │
│      │  ~/.claude/ide/<port>.lock                     │           │
│      │   { pid, workspaceFolders, port, authToken }   │           │
│      └────────────────────────────────────────────────┘           │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

The connection flow:

1. `dev` launches a kitty tab with nvim. Nvim starts and **eager-loads**
   `coder/claudecode.nvim`, which binds a WebSocket port and writes a
   lockfile to `~/.claude/ide/<port>.lock`.
2. `dev` waits for that lockfile (snapshot-diff: it tracks new lockfiles
   appearing after nvim launches, so multi-tab on the same project works).
3. `dev` reads the port from the lockfile filename and launches
   `CLAUDE_CODE_SSE_PORT=<port> ENABLE_IDE_INTEGRATION=true claude --ide`
   in the right kitty pane. Claude connects deterministically to *this*
   nvim, not whichever lockfile happens to be alphabetically first.
4. While the session is live, the fs watcher in `nvim/lua/config/autocmds.lua`
   detects external file changes (debounced) and runs `:checktime` so
   buffers reload when Claude edits a file — independently of nvim's
   focus state.

## Prerequisites

- **kitty** with remote control enabled. In `~/.config/kitty/kitty.conf`:
  ```
  allow_remote_control yes
  listen_on unix:/tmp/mykitty
  ```
  Then *fully* quit kitty (cmd-Q) and reopen — the socket isn't created
  on a config reload.
- **claude** CLI (Claude Code) in `$PATH`.
- **nvim** with the [`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim)
  plugin configured with `lazy = false` so the WebSocket server starts
  on nvim startup, not on first keybind. Reference config:
  `~/Dev/drucial-dots/nvim/lua/plugins/claudecode.lua`.
- **fzf** for the project picker.
- **jq** (recommended). Without it, lockfile parsing falls back to grep
  and `dev close` won't work at all.

Run `dev check` to verify all of the above + that the end-to-end flow
actually wires up a WebSocket lockfile.

## Install on a fresh machine

1. Symlink or place this `dev` script somewhere in `$PATH`
   (typically `~/.local/bin/dev`).
2. Install the prerequisites above (`brew install kitty fzf jq`,
   the Claude CLI per its instructions, your nvim distro).
3. Edit `~/.config/kitty/kitty.conf` to enable remote control (see above).
   Relaunch kitty.
4. Ensure your nvim config eager-loads `coder/claudecode.nvim` (`lazy = false`).
5. Run `dev check` — everything should be green.

## Usage

```
dev                    Open a default 3-pane session (nvim / shell | claude)
                       for a project under ~/Dev (fzf-picked).

dev -s                 Open a simple 2-pane session (nvim | shell). No claude.

dev .                  Build the layout in the CURRENT kitty tab using $PWD
                       as the project. The current shell becomes nvim; claude
                       and shell panes are added. The current tab must have
                       exactly one window (a fresh tab).

dev close              Soft-close a dev session. Pops fzf with the live
                       sessions tracked in $DEV_SESSIONS_FILE.

dev close .            Soft-close the CURRENT kitty tab, if it's a tracked
                       dev session.

dev check              Health-check the workflow. Runs binary + runtime checks
                       then exercises the full IDE-connection flow with a
                       headless nvim. Exit 0 if all PASS, 1 on any FAIL.

dev --help, dev -h     Print the help.
```

### Examples

```bash
# Fresh project session
dev

# Wider Claude pane this session only
DEV_CLAUDE_BIAS=40 dev

# Already cd'd into a project? Build in place.
cd ~/Dev/foo
dev .

# Done for the day
dev close
```

## Environment variables

| Variable                | Default                              | Purpose                                                          |
| ----------------------- | ------------------------------------ | ---------------------------------------------------------------- |
| `DEV_CLAUDE_BIAS`       | `30`                                 | Claude pane width %                                              |
| `DEV_SHELL_BIAS`        | `30`                                 | Shell pane size %                                                |
| `DEV_LOCKFILE_TIMEOUT`  | `5`                                  | Seconds to wait for nvim's IDE lockfile                          |
| `DEV_SHELL_READY_WAIT`  | `0.3`                                | Seconds to wait for a freshly-spawned shell to be ready          |
| `DEV_SESSIONS_FILE`     | `~/.cache/dev/sessions.json`         | Session-state file for `dev close`                               |
| `DEV_ANY_CWD`           | unset                                | `1` allows `dev .` from cwds outside `~/Dev/`                    |

## Troubleshooting

### Claude pane shows "None" in `/ide`

The plugin's lockfile didn't appear (or didn't match) before `claude` was
launched. Typical causes:

- `coder/claudecode.nvim` isn't eager-loaded — it lazy-loads on keys, so
  the WebSocket server doesn't start until you press a keybind. Set
  `lazy = false` on the plugin spec.
- A previous nvim crashed and left a stale lockfile that confuses the
  scan. `dev` prunes stale lockfiles automatically, but if you're using
  plain `claude --ide` outside of `dev`, run
  `rm ~/.claude/ide/*.lock` and start fresh.
- The nvim startup took longer than `DEV_LOCKFILE_TIMEOUT`. Bump it:
  `DEV_LOCKFILE_TIMEOUT=10 dev`.

In the running Claude pane, you can always run `/ide` and manually select
the Neovim instance.

### Buffer doesn't refresh after Claude edits a file

The fs watcher in `autocmds.lua` is the focus-independent reload path.
If it's silent:

- Check `:messages` in nvim for a one-shot WARN about
  `vim.uv.new_fs_event()` returning nil. That means the watcher failed
  to register; the rest of the session is fine but you'll need to
  `:checktime` manually or refocus nvim to reload buffers.
- The watcher restarts on `DirChanged`. If your cwd is wrong, `:cd <project>`
  in nvim re-attaches the watcher to the right directory.

### `W11: File changed on disk` warnings

Expected when nvim's buffer is modified AND the same file changes on
disk (Claude editing it from outside). Dismiss with:

- `e!` to take the disk version (discards your unsaved changes).
- `:w!` to keep your buffer version (overwrites Claude's edit).

Either is your choice — nvim's prompt prevents silent data loss.

### `kitty @ ...` errors / socket weirdness after sleep-wake

macOS sleep/wake can leave kitty's listener socket in a half-broken
state. The cheapest fix is to fully quit kitty (cmd-Q) and reopen.
`dev check` will tell you if the remote-control socket is responding.

### Switching git branches inside a `dev` tab

Supported and works as expected. `git checkout other-branch` in the
shell pane triggers a single debounced `:checktime`; open buffers reload
to the new branch's content (or show `W11` if you have unsaved local
edits). Claude stays connected — the lockfile is keyed to the project
path, not the branch.

### Git worktrees in `~/Dev/`

If your worktrees live under `~/Dev/` (e.g. `myrepo`, `myrepo.feature-foo`),
they "just work": each worktree is its own fzf entry with its own kitty
tab, nvim, lockfile, and Claude session. No naming convention required
by `dev`.

### Multiple `dev` tabs for the same project

Fully supported. Each `dev` invocation matches *its own* nvim via the
snapshot-diff lockfile algorithm, so tab 2's Claude connects to tab 2's
nvim, not tab 1's. Each tab is an independent Claude session.

### `dev .` refuses with "current tab already has N windows"

The 3-pane layout assumes an empty tab. Open a fresh tab (`cmd+t`) and
try again.

### `dev .` refuses with "cwd is not under ~/Dev"

Either move/symlink your project under `~/Dev/`, or escape the check
once: `DEV_ANY_CWD=1 dev .`.

### `dev close` says "nvim has unsaved changes"

The script sent `:qa` to nvim, but nvim is still alive — usually because
of a modified buffer. Save (`:w`) or force-quit (`:qa!`) in the nvim
pane, then re-run `dev close`.

### Tmux inside kitty

Unsupported. `dev` orchestrates via `kitty @ send-text`, which delivers
keystrokes to kitty windows, not into tmux panes. Run `dev` directly
against kitty.

### Symlinks / case-insensitive APFS

The fs watcher operates at the inode level via `vim.uv.new_fs_event`,
so changes are detected even when the buffer's path differs by case or
symlink resolution from the path Claude wrote. `:checktime` handles the
reload.

## Files involved

- `~/Dev/scripts/dev` — this script.
- `~/Dev/drucial-dots/nvim/lua/plugins/claudecode.lua` — plugin spec
  (`lazy = false`, external terminal provider, env-passthrough).
- `~/Dev/drucial-dots/nvim/lua/config/autocmds.lua` — recursive
  workspace fs watcher.
- `~/Dev/drucial-dots/nvim/lua/plugins/lualine.lua` — statusline
  Claude-connected indicator.
- `~/.config/kitty/kitty.conf` — remote control enabled.
- `~/.claude/ide/<port>.lock` — IDE handshake lockfile (managed by
  claudecode.nvim, pruned by `dev` on launch).
- `~/.cache/dev/sessions.json` — session-state file (for `dev close`).

## Future work

### Replace `sessions.json` with kitty user-vars

The current state file is a hint that can drift from reality (e.g. a
session that gains extra splits, or one whose windows are manually
closed) — the prune-on-`dev close` cycle papers over most cases but not
all (see drift modes in the troubleshooting section).

A more robust approach is to tag each pane with a kitty user-var at
launch and let kitty be the source of truth. The plan of attack:

1. **Pre-flight verify**: confirm `kitty @ set-user-vars --match id:N
   key=value` works on the installed kitty and that the var appears in
   `kitty @ ls`'s window JSON under `user_vars`.
2. **Helpers**: small wrappers `_dev_mark_window`, `_dev_find_dev_tabs`
   (tabs containing a window with `dev_role=nvim`), and
   `_dev_window_by_role <tab_id> <role>`.
3. **Tag at launch**: in `_dev_build_layout`, after each `kitty @ launch`
   capturing a window id, set `dev_role` (nvim/claude/shell) on it and
   `dev_project` / `dev_started` on the nvim window.
4. **Rewrite `_dev_close`**: list dev tabs via `_dev_find_dev_tabs`,
   fzf-pick (or `.` for current), resolve each pane's window id by
   role, then send the existing close signals.
5. **Delete**: `_dev_record_session`, `_dev_prune_sessions`,
   `$DEV_SESSIONS_FILE`, and the corresponding troubleshooting/help text.
6. **Migration**: on first run of the new version, if
   `~/.cache/dev/sessions.json` exists, just `rm` it (it's stale by
   definition — only tab-id values, no `dev_role` tags). Document in
   the release note.

Net effect: zero local state, kitty handles cleanup automatically when
windows/tabs die, drift modes go away. Cost: ~50–80 lines net, plus
edge-case thinking for `dev .` (which doesn't `kitty @ launch` for the
nvim window — it sends `nvim\n` to the existing window, so tagging
needs to happen against the captured `_dev_current_window_id`).
