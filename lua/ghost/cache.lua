-- Answers on disk: <git root>/.ghost/<relative path>.json, meant to be
-- committed. Files outside any repo fall back to nvim's cache dir.
local M = {}

local loaded = {} -- cache file path -> { key -> entry }

local fields = { "question", "kind", "lang", "body", "model", "created" }

local function path(file)
  local root = vim.fs.root(file, ".git")
  if root then
    return root .. "/.ghost/" .. file:sub(#root + 2) .. ".json"
  end
  return vim.fn.stdpath("cache") .. "/ghost/files" .. file .. ".json"
end

-- Hand-rolled so the file diffs well: sorted keys, one field per line.
local function encode(entries)
  local keys = vim.tbl_keys(entries)
  if #keys == 0 then
    return "{}\n"
  end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local lines = {}
    for _, f in ipairs(fields) do
      if entries[k][f] ~= nil then
        table.insert(lines, ("    %s: %s"):format(vim.json.encode(f), vim.json.encode(entries[k][f])))
      end
    end
    table.insert(out, ("  %s: {\n%s\n  }"):format(vim.json.encode(k), table.concat(lines, ",\n")))
  end
  return "{\n" .. table.concat(out, ",\n") .. "\n}\n"
end

local function load(file)
  local p = path(file)
  if not loaded[p] then
    local f = io.open(p, "r")
    local ok, data = false, nil
    if f then
      ok, data = pcall(vim.json.decode, f:read("*a"))
      f:close()
    end
    loaded[p] = ok and type(data) == "table" and data or {}
  end
  return loaded[p], p
end

local function save(entries, p)
  vim.fn.mkdir(vim.fs.dirname(p), "p")
  local f = assert(io.open(p, "w"))
  f:write(encode(entries))
  f:close()
end

function M.get(file, key)
  return (load(file))[key]
end

function M.put(file, key, entry)
  local entries, p = load(file)
  entries[key] = entry
  save(entries, p)
end

-- Drop answers whose question is no longer in the file.
function M.prune(file, live)
  local entries, p = load(file)
  local changed = false
  for k in pairs(entries) do
    if not live[k] then
      entries[k] = nil
      changed = true
    end
  end
  if changed then
    save(entries, p)
  end
end

return M
