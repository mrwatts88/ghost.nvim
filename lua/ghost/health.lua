-- :checkhealth ghost
local M = {}

local function first_line(s)
  return (vim.trim(s or ""):match("[^\n]+")) or "?"
end

function M.check()
  local h = vim.health
  local config = require("ghost").config

  h.start("ghost.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim 0.10 or newer is required")
  end

  local exe = require("ghost.backend").executable(config)
  local install = {
    claude = "Install Claude Code: https://github.com/anthropics/claude-code",
    codex = "Install the Codex CLI: https://github.com/openai/codex",
  }
  if vim.fn.executable(exe) == 1 then
    local res = vim.system({ exe, "--version" }, { text = true }):wait()
    h.ok(("backend %s: %s"):format(exe, first_line(res.stdout)))
    h.info(("model: %s, effort: %s"):format(config.model or "backend default", config.effort or "backend default"))
    h.info(("If answers fail with an auth error, run `%s` once in a terminal to log in."):format(exe))
  else
    h.error(exe .. " not found", {
      install[config.backend] or "Install the CLI for your backend",
      "or set `cmd` to the executable's path",
    })
  end

  h.start("ghost.nvim: setup context")
  local ctx = config.context
  h.info(
    ("nvim keymaps: %s, tmux: %s, shell: %s"):format(
      ctx.nvim and "on" or "off",
      ctx.tmux and "on" or "off",
      ctx.shell or "off"
    )
  )
  if ctx.tmux and vim.fn.executable("tmux") == 0 then
    h.info("tmux not found; tmux bindings will be skipped")
  end
  local text = require("ghost.digest").build()
  h.ok(("%d bytes sent with each question; review it with :Ghost setup"):format(#text))
end

return M
