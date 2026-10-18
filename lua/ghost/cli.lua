-- Entry point for bin/ghost: one question from the shell, answer on stdout.
-- Runs inside a headless nvim with the user's full config, so the setup
-- digest is the same one the editor uses.
local M = {}

local function finish(code)
  io.stdout:flush()
  vim.cmd(code == 0 and "qa!" or "cquit " .. code)
end

function M.run()
  local question = vim.trim(vim.env.GHOST_QUESTION or "")
  if question == "" then
    io.stderr:write("usage: ghost <question>\n")
    return finish(2)
  end

  -- Headless never fires VeryLazy, which is when LazyVim sets its keymaps.
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })

  vim.schedule(function()
    local backend = require("ghost.backend")
    local digest = require("ghost.digest")
    local prompt = require("ghost.prompt")
    local ghost = require("ghost")
    local config = ghost.config

    -- One-off overrides: GHOST_BACKEND=codex GHOST_EFFORT=low ghost ...
    for _, k in ipairs({ "backend", "model", "effort" }) do
      local v = vim.env["GHOST_" .. k:upper()]
      if v and v ~= "" then
        config[k] = v
      end
    end

    local cwd = vim.fn.getcwd()
    local opts = ghost.backend_opts(cwd)
    local done = false
    backend.ask(prompt.shell(question, cwd, digest.get()), prompt.system, opts, function(ans, err)
      if err then
        io.stderr:write("ghost: " .. err .. "\n")
      else
        io.stdout:write(vim.trim(ans.body) .. "\n")
      end
      done = err and 1 or 0
    end)
    vim.wait(config.timeout_ms + 5000, function()
      return done ~= false
    end, 50)
    finish(done == false and 1 or done)
  end)
end

return M
