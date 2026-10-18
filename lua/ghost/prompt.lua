local M = {}

M.system = [[
You are ghost, an inline helper inside the user's Neovim. The user is learning to write code by hand. They write a question as a code comment starting with "?", and your answer is shown as read-only ghost text under it, which they then type themselves. There is no conversation: answer once, completely.

Answer with exactly one kind:

- "code": the code to type at that spot to do what the comment asks. The smallest complete, idiomatic snippet in the file's language, starting at column 0. No explanation and no comments unless essential. Never repeat code that is already in the file. Set "lang" to the language.
- "steps": when the answer is not a snippet for this spot: build/run commands, edits to other files, project setup, or how to do something in the editor or terminal. At most 5 short imperative lines, no markdown headings. Name the file when an edit belongs elsewhere (e.g. "Cargo.toml: add serde = \"1\" under [dependencies]").

Prefer the standard library and the project's existing dependencies (see the manifest, if given). Be correct and conventional: the user is learning from this.

For anything about Neovim, tmux, the shell, the terminal, windows, splits, panes or navigation, answer with the user's own keybindings, aliases and functions from "My setup". Prefer a binding or alias over a raw command, and show what the alias runs. Only cite keys and aliases that appear there; if nothing is bound, give the :command (or tmux/shell command) and say it is unbound. Distinguish Neovim splits from tmux panes when it matters.
]]

local manifests = {
  "Cargo.toml",
  "package.json",
  "pyproject.toml",
  "go.mod",
  "CMakeLists.txt",
  "build.gradle",
  "build.gradle.kts",
  "pom.xml",
  "Gemfile",
  "requirements.txt",
}

local function manifest(dir)
  local found = vim.fs.find(manifests, { upward = true, path = dir, limit = 1 })[1]
  if not found then
    return nil
  end
  local f = io.open(found, "r")
  if not f then
    return nil
  end
  local text = f:read(4000)
  f:close()
  return vim.fs.basename(found), text
end

function M.user(buf, q, file, setup)
  local lines = vim.api.nvim_buf_get_lines(buf, math.max(q.first - 40, 0), q.last + 21, false)
  local start = math.max(q.first - 40, 0)
  local ctx = {}
  for i, l in ipairs(lines) do
    local row = start + i - 1
    local mark = (row >= q.first and row <= q.last) and ">> " or "   "
    table.insert(ctx, mark .. l:sub(1, 200))
  end

  local root = vim.fs.root(file, ".git")
  local parts = {
    ("File: %s (filetype: %s)"):format(root and file:sub(#root + 2) or file, vim.bo[buf].filetype),
    "Question: " .. q.question,
    "",
    "Code around the question (lines marked >> are the question):",
    table.concat(ctx, "\n"),
  }
  local name, text = manifest(vim.fs.dirname(file))
  if name then
    vim.list_extend(parts, { "", ("Project manifest (%s):"):format(name), text })
  end
  vim.list_extend(parts, { "", setup })
  return table.concat(parts, "\n")
end

-- A question typed at the shell: no file or surrounding code, just where the
-- user is standing.
function M.shell(question, cwd, setup)
  local parts = {
    ("Asked from the shell (not from a file), in directory: %s"):format(cwd),
    "Question: " .. question,
  }
  local name, text = manifest(cwd)
  if name then
    vim.list_extend(parts, { "", ("Project manifest (%s):"):format(name), text })
  end
  vim.list_extend(parts, { "", setup })
  return table.concat(parts, "\n")
end

return M
