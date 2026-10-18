-- Answers on disk: one store per project, <git root>/.ghost/answers.json,
-- meant to be committed. Files outside any repo share one store in nvim's
-- cache dir. Entries are keyed by question + filetype, and each lists the
-- files that ask it; an entry goes away once no file does.
local M = {}

local stores = {} -- store path -> { key -> entry }

local fields = { "question", "filetype", "files", "kind", "lang", "body", "model", "created" }

local function root_of(file)
  return vim.fs.root(file, ".git")
end

local function store_path(file)
  local root = root_of(file)
  if root then
    return root .. "/.ghost/answers.json"
  end
  return vim.fn.stdpath("cache") .. "/ghost/answers.json"
end

-- How a file is listed in an entry's `files`: relative to the repo root.
local function rel(file)
  local root = root_of(file)
  return root and file:sub(#root + 2) or file
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

local function read_json(p)
  local f = io.open(p, "r")
  if not f then
    return nil
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(data) == "table" and data or nil
end

local function save(entries, p)
  vim.fn.mkdir(vim.fs.dirname(p), "p")
  local f = assert(io.open(p, "w"))
  f:write(encode(entries))
  f:close()
end

-- Earlier versions kept one .ghost/<path>.json per source file, keyed by the
-- question alone. Fold those into the project store, then remove them.
local function migrate(dir, entries)
  local old = {}
  for name, kind in vim.fs.dir(dir, { depth = math.huge }) do
    if kind == "file" and name:match("%.json$") and name ~= "answers.json" then
      table.insert(old, name)
    end
  end
  if #old == 0 then
    return false
  end
  local key = require("ghost.trigger").key
  for _, name in ipairs(old) do
    local src = name:gsub("%.json$", "")
    local ft = vim.filetype.match({ filename = src }) or ""
    for _, e in pairs(read_json(dir .. "/" .. name) or {}) do
      if type(e) == "table" and e.question then
        local k = key(e.question, ft)
        local have = entries[k]
        if have then
          if not vim.list_contains(have.files, src) then
            table.insert(have.files, src)
          end
        else
          e.filetype, e.files = ft, { src }
          entries[k] = e
        end
      end
    end
  end
  save(entries, dir .. "/answers.json")
  for _, name in ipairs(old) do
    os.remove(dir .. "/" .. name)
  end
  -- Drop the now-empty mirror directories, deepest first.
  table.sort(old, function(a, b)
    return #a > #b
  end)
  for _, name in ipairs(old) do
    local d = vim.fs.dirname(dir .. "/" .. name)
    while d ~= dir and vim.uv.fs_rmdir(d) do
      d = vim.fs.dirname(d)
    end
  end
  return true
end

local function load(file)
  local p = store_path(file)
  if not stores[p] then
    stores[p] = read_json(p) or {}
    for _, entry in pairs(stores[p]) do
      entry.files = entry.files or {}
    end
    if root_of(file) and vim.uv.fs_stat(vim.fs.dirname(p)) then
      migrate(vim.fs.dirname(p), stores[p])
    end
  end
  return stores[p], p
end

local function list_file(entry, name)
  if vim.list_contains(entry.files, name) then
    return false
  end
  table.insert(entry.files, name)
  table.sort(entry.files)
  return true
end

-- The answer for this question, from anywhere in the project. A file that
-- shows an answer is recorded as using it, so moving a question to another
-- file keeps the answer even after the old file is saved without it.
function M.get(file, key)
  local entries, p = load(file)
  local entry = entries[key]
  if entry and list_file(entry, rel(file)) then
    save(entries, p)
  end
  return entry
end

function M.put(file, key, entry)
  local entries, p = load(file)
  local files = entries[key] and entries[key].files or {}
  entry.files = files
  list_file(entry, rel(file))
  entries[key] = entry
  save(entries, p)
end

-- After a save: this file no longer uses answers whose question it no longer
-- has. An answer no file uses is deleted.
function M.prune(file, live)
  local entries, p = load(file)
  local name = rel(file)
  local changed = false
  for k, entry in pairs(entries) do
    if not live[k] and vim.list_contains(entry.files, name) then
      entry.files = vim.tbl_filter(function(f)
        return f ~= name
      end, entry.files)
      if #entry.files == 0 then
        entries[k] = nil
      end
      changed = true
    end
  end
  if changed then
    save(entries, p)
  end
end

return M
