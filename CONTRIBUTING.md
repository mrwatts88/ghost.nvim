# Contributing to ghost.nvim

Thanks for helping. Issues and pull requests are welcome: bug reports,
support for new backends, comment styles that aren't detected, and better
answers.

## The one rule: it teaches, it doesn't chat

ghost exists so people learn to write code by hand. Before proposing a feature,
check it against these:

- **Nothing is ever inserted into the buffer.** No accept key, no "apply".
  Typing it yourself is the point.
- **One question, one answer.** No follow-ups, chat panes, or threads.
- **Answers are short.** Either a snippet or a few steps.
- **Answers are cached.** Reopening a file shouldn't cost a request.

Features that move toward autocomplete or conversation will usually be
declined, however useful they are on their own. If you're unsure, open an issue
before writing code.

## Development setup

Clone the repo and point your plugin manager at the checkout. With lazy.nvim:

```lua
{
  dir = "~/code/ghost.nvim", -- your clone
  name = "ghost.nvim",
  event = "VeryLazy",
  opts = {},
}
```

Restart Neovim after changes, or `:Lazy reload ghost.nvim`.

## Layout

```text
lua/ghost/
  init.lua      setup(), config defaults, keymaps, autocmds, :Ghost
  trigger.lua   finds `?` comments (comment leaders + treesitter check)
  prompt.lua    the system prompt and per-question context
  digest.lua    the "my setup" context: keymaps, tmux, shell
  backend.lua   backend adapters (claude, codex, custom)
  cache.lua     .ghost/ read / write / prune
  render.lua    virtual lines and syntax highlighting
  health.lua    :checkhealth ghost
  cli.lua       entry point for bin/ghost
bin/ghost       shell CLI (runs headless Neovim)
```

## Adding a backend

A backend is a function in `M.adapters` in `lua/ghost/backend.lua`:

```lua
function M.adapters.mycli(prompt, system, opts)
  local argv = { opts.cmd or "mycli", "--read-only" }
  -- map opts.model / opts.effort to the CLI's flags, then append opts.args
  return argv, stdin_text, function(res) -- res is the vim.system() result
    return answer_table_or_nil, error_message_or_nil
  end
end
```

Requirements:

- **Read-only.** The CLI must not be able to edit files or run commands that
  change anything. Use its sandbox or tool-disabling flags.
- **Structured output** if the CLI supports it, using the shared `schema`.
  Otherwise use `inline()` and `decode_loose()`, as the custom backend does.
- **Strip whatever it loads by default** (plugins, MCP servers, project
  instructions), when it can. Less overhead means faster, cheaper answers.
- Add an install hint to `health.lua` and document the backend in the README.

## Style

- Format with [StyLua](https://github.com/JohnnyMorganz/StyLua) using the
  repo's `.stylua.toml`: `stylua lua/`.
- Match the surrounding code. Comments explain *why*, not *what*.
- Keep it dependency-free: only Neovim's standard library, no plugin
  requirements.

## Testing

There's no automated test suite yet. Contributions toward one are welcome. Until
then, please check by hand:

1. `:checkhealth ghost` passes.
2. A `?` question in a file of the language you touched gets detected
   (`:lua =require("ghost.trigger").scan(0)`), answered, and rendered.
3. Reopening the file shows the cached answer without a new request.
4. If you touched `backend.lua`: a code answer and a steps answer both come
   back, and an error (e.g. a bogus `model`) shows a readable `✗` line
   instead of a stack trace.
5. If you touched `digest.lua`: check `:Ghost setup`, and make sure nothing
   sensitive gets in under the default `shell = "aliases"`.

Mention what you tested in the PR description.

## Pull requests

- Keep each PR to one change, and explain the problem it solves.
- Update `README.md` when behavior or configuration changes.
- Be kind in reviews and issues.
