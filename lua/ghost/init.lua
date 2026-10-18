local backend = require("ghost.backend")
local cache = require("ghost.cache")
local digest = require("ghost.digest")
local prompt = require("ghost.prompt")
local render = require("ghost.render")
local trigger = require("ghost.trigger")

local M = {}

M.config = {
  -- Which AI CLI answers, using the login it already has: "claude" (Claude
  -- Code), "codex" (OpenAI Codex CLI), or { cmd = { ... } } for any CLI that
  -- reads the prompt on stdin and prints a JSON answer.
  backend = "claude",
  -- Passed straight to the CLI. nil = its default (claude: "sonnet";
  -- codex: whatever ~/.codex/config.toml says).
  model = nil,
  -- claude: low | medium | high | xhigh | max. codex: minimal | low | medium | high.
  effort = nil,
  -- Extra flags appended to the built-in backend's command.
  args = {},
  -- Executable path, when it isn't on $PATH under the backend's name.
  cmd = nil,
  -- Ask every unanswered question in the file on :w. Off: only the ask key asks.
  ask_on_save = false,
  max_lines = 30,
  timeout_ms = 90000,
  -- Set to false to define your own mappings to require("ghost").ask etc.
  keys = {
    ask = "<leader>ii",
    toggle = "<leader>it",
    expand = "<leader>ie",
  },
  -- What "my setup" context is sent with each question, so answers use your
  -- own keybindings and aliases. See :Ghost setup for exactly what goes out.
  context = {
    nvim = true, -- keymaps that have a description
    tmux = true, -- effective tmux bindings and your tmux.conf
    -- "aliases": only alias/function/bindkey lines from shell_files, with the
    -- comment above each. "full": the whole files. false: nothing.
    shell = "aliases",
    shell_files = { "~/.zshrc", "~/.bashrc", "~/.config/fish/config.fish" },
  },
}

local pending = {} -- "file:key" -> true while a request runs
local errors = {} -- "file:key" -> message from the last failed request
local view = {} -- buf -> { hidden = bool, expanded = bool }

local function state(buf)
  view[buf] = view[buf] or {}
  return view[buf]
end

local function file_of(buf)
  if vim.bo[buf].buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  return vim.uv.fs_realpath(name) or vim.fs.normalize(name)
end

local function answer_rows(buf, entry, expanded)
  local body = vim.trim(entry.body)
  local rows = entry.kind == "code" and render.code(body, entry.lang, buf)
    or render.plain(vim.split(body, "\n", { plain = true }), "GhostText")
  local max = M.config.max_lines
  if expanded or #rows <= max then
    return rows
  end
  local shown = vim.list_slice(rows, 1, max)
  table.insert(shown, { { ("… +%d more (%s)"):format(#rows - max, M.config.keys.expand), "GhostText" } })
  return shown
end

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  render.clear(buf)
  local file = file_of(buf)
  if not file or state(buf).hidden then
    return
  end
  for _, q in ipairs(trigger.scan(buf)) do
    local id = file .. ":" .. q.key
    if pending[id] then
      render.draw(buf, q, render.plain({ "⋯ thinking" }, "GhostText"))
    elseif errors[id] then
      local msg = ("✗ %s  (%s to retry)"):format(errors[id], M.config.keys.ask)
      render.draw(buf, q, render.plain({ msg }, "GhostError"))
    else
      local entry = cache.get(file, q.key)
      if entry then
        render.draw(buf, q, answer_rows(buf, entry, state(buf).expanded))
      end
    end
  end
end

function M.backend_opts(cwd)
  local c = M.config
  return {
    backend = c.backend,
    cmd = c.cmd,
    model = c.model,
    effort = c.effort,
    args = c.args,
    timeout_ms = c.timeout_ms,
    cwd = cwd,
  }
end

local function request(buf, q)
  local file = file_of(buf)
  if not file then
    return
  end
  local id = file .. ":" .. q.key
  if pending[id] then
    return
  end
  pending[id] = true
  errors[id] = nil
  M.refresh(buf)

  local opts = M.backend_opts(vim.fs.dirname(file))
  backend.ask(prompt.user(buf, q, file, digest.get()), prompt.system, opts, function(ans, err)
    pending[id] = nil
    if err then
      errors[id] = err
    else
      cache.put(file, q.key, {
        question = q.question,
        kind = ans.kind,
        lang = ans.lang,
        body = ans.body,
        -- Which model answered, or at least which backend did.
        model = M.config.model or (type(M.config.backend) == "string" and M.config.backend or "custom"),
        created = os.date("%Y-%m-%d"),
      })
    end
    M.refresh(buf)
  end)
end

-- Ask (or re-ask) the question under the cursor.
function M.ask()
  local buf = vim.api.nvim_get_current_buf()
  local q = trigger.at_cursor(buf)
  if not q then
    return vim.notify("ghost: cursor is not on a `?` comment", vim.log.levels.WARN)
  end
  request(buf, q)
end

function M.toggle()
  local s = state(vim.api.nvim_get_current_buf())
  s.hidden = not s.hidden
  M.refresh()
end

function M.expand()
  local s = state(vim.api.nvim_get_current_buf())
  s.expanded = not s.expanded
  M.refresh()
end

local function on_save(buf)
  local file = file_of(buf)
  if not file then
    return
  end
  local live = {}
  for _, q in ipairs(trigger.scan(buf)) do
    live[q.key] = true
    if M.config.ask_on_save and not cache.get(file, q.key) then
      request(buf, q)
    end
  end
  cache.prune(file, live)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  render.setup_hl()

  local k = M.config.keys
  if k then
    vim.keymap.set("n", k.ask, M.ask, { desc = "Ghost: Ask Question Under Cursor" })
    vim.keymap.set("n", k.toggle, M.toggle, { desc = "Ghost: Toggle Answers" })
    vim.keymap.set("n", k.expand, M.expand, { desc = "Ghost: Expand Long Answers" })
    pcall(function()
      -- Label the prefix the keys share, e.g. <leader>i for <leader>ii.
      require("which-key").add({ { k.ask:sub(1, -2), group = "ghost" } })
    end)
  end

  local group = vim.api.nvim_create_augroup("ghost", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "InsertLeave" }, {
    group = group,
    callback = function(ev)
      M.refresh(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      on_save(ev.buf)
      M.refresh(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = render.setup_hl })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      view[ev.buf] = nil
    end,
  })

  vim.api.nvim_create_user_command("Ghost", function(cmd)
    local sub = cmd.args
    if sub == "" or sub == "ask" then
      M.ask()
    elseif sub == "toggle" then
      M.toggle()
    elseif sub == "expand" then
      M.expand()
    elseif sub == "setup" then
      digest.build()
      vim.cmd.edit(digest.path())
    else
      vim.notify("ghost: unknown subcommand " .. sub, vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    complete = function()
      return { "ask", "toggle", "expand", "setup" }
    end,
    desc = "Ghost: ask | toggle | expand | setup",
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.refresh(buf)
    end
  end
end

return M
