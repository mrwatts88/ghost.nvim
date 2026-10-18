-- "My setup": the keybindings actually in effect, read from the live nvim and
-- tmux config rather than written by hand, so it can't go stale. Built once
-- per nvim session, so it always matches the machine it runs on.
local M = {}

local cached

local modes = { "n", "x", "o", "i", "t" }

local function nvim_maps()
  local out = {}
  local leader = vim.g.mapleader or "\\"
  for _, mode in ipairs(modes) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      if m.desc and m.desc ~= "" and not m.lhs:find("<Plug>") then
        local lhs = m.lhs
        if vim.startswith(lhs, leader) then
          lhs = "<leader>" .. vim.fn.keytrans(lhs:sub(#leader + 1))
        else
          lhs = vim.fn.keytrans(lhs)
        end
        table.insert(out, ("%s  %-14s %s"):format(mode, lhs, m.desc))
      end
    end
  end
  table.sort(out)
  return out
end

local function read(p)
  local f = io.open(vim.fn.expand(p), "r")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

local function tmux_conf()
  for _, p in ipairs({ "~/.config/tmux/tmux.conf", "~/.tmux.conf" }) do
    p = vim.fn.expand(p)
    if vim.uv.fs_stat(p) then
      return p
    end
  end
end

-- `list-keys`, not `list-keys -N`: -N only shows bindings that carry a note,
-- which leaves out every custom bind in tmux.conf. A throwaway server on its
-- own socket loads the config without touching the running one.
local function tmux_keys(conf)
  if vim.fn.executable("tmux") == 0 then
    return nil
  end
  local cmd = { "tmux", "-L", "ghost-digest" }
  if conf then
    vim.list_extend(cmd, { "-f", conf })
  end
  vim.list_extend(cmd, { "start-server", ";", "list-keys", "-T", "prefix", ";", "list-keys", "-T", "root" })
  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  local out = {}
  for line in res.stdout:gmatch("[^\n]+") do
    line = line:gsub("^bind%-key%s+", ""):gsub("%s+", " ")
    -- Skip the giant display-menu definitions; they're noise.
    if #line < 160 then
      table.insert(out, line)
    end
  end
  return out
end

local definition = {
  "^%s*alias%s", -- sh/zsh/bash/fish
  "^%s*abbr%s", -- fish
  "^%s*function%s", -- function foo / fish
  "^%s*[%w_.:-]+%s*%(%)", -- foo() {
  "^%s*bindkey%s", -- zsh
  "^%s*bind%s", -- bash/fish
}

-- Only the lines that define things you'd type, each with the comment block
-- directly above it. The rest of a shell rc file is where exported tokens
-- and other secrets tend to live, so it is never sent.
local function shell_definitions(text)
  local out, comments = {}, {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:match("^%s*#") then
      table.insert(comments, line)
    else
      for _, pat in ipairs(definition) do
        if line:match(pat) then
          vim.list_extend(out, comments)
          table.insert(out, line)
          break
        end
      end
      comments = {}
    end
  end
  return out
end

function M.build(ctx)
  ctx = ctx or require("ghost").config.context
  local lazyvim = package.loaded["lazyvim"] ~= nil or rawget(_G, "LazyVim") ~= nil
  local sections = {
    ("# My setup (%s)"):format(vim.uv.os_uname().sysname),
    "<leader> is " .. vim.fn.keytrans(vim.g.mapleader or "\\") .. ".",
  }
  if lazyvim then
    vim.list_extend(sections, {
      'Neovim distribution: LazyVim. The "tabs" across the top are bufferline buffers, so "tab" usually means a buffer; answer for buffers first, then mention real tabpages briefly.',
    })
  end

  if ctx.nvim then
    vim.list_extend(sections, { "", "## Neovim keymaps (mode, keys, description)", table.concat(nvim_maps(), "\n") })
  end

  if ctx.tmux then
    local conf = tmux_conf()
    local keys = tmux_keys(conf)
    if keys then
      vim.list_extend(sections, { "", "## tmux bindings (effective, from list-keys)", table.concat(keys, "\n") })
    end
    local text = conf and read(conf)
    if text then
      vim.list_extend(sections, { "", "## tmux.conf (" .. conf .. ")", text })
    end
  end

  if ctx.shell then
    for _, p in ipairs(ctx.shell_files) do
      local text = read(p)
      if text then
        local body = ctx.shell == "full" and text or table.concat(shell_definitions(text), "\n")
        if body ~= "" then
          vim.list_extend(sections, { "", ("## %s (aliases, functions, shell keybindings)"):format(p), body })
        end
      end
    end
  end

  cached = table.concat(sections, "\n")

  local p = M.path()
  vim.fn.mkdir(vim.fs.dirname(p), "p")
  local f = io.open(p, "w")
  if f then
    f:write(cached)
    f:close()
  end
  return cached
end

function M.path()
  return vim.fn.stdpath("cache") .. "/ghost/setup.md"
end

function M.get()
  return cached or M.build()
end

return M
