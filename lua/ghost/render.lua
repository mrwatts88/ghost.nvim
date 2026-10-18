-- Ghost text: virtual lines under the question. They are not part of the
-- buffer, can't be edited, and are never written to the file.
local M = {}

M.ns = vim.api.nvim_create_namespace("ghost")

function M.setup_hl()
  vim.api.nvim_set_hl(0, "GhostText", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "GhostBar", { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, "GhostError", { link = "DiagnosticError", default = true })
  -- Layered over syntax colors, so ghost code never passes for real code.
  vim.api.nvim_set_hl(0, "GhostCode", { italic = true, default = true })
end

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
end

-- Each row is a list of { text, hl } chunks.
function M.draw(buf, q, rows)
  local tab = string.rep(" ", vim.bo[buf].tabstop)
  local bar = q.indent:gsub("\t", tab) .. "┆ "
  local virt = {}
  for _, row in ipairs(rows) do
    local line = { { bar, "GhostBar" } }
    for _, chunk in ipairs(row) do
      table.insert(line, { (chunk[1]:gsub("\t", tab)), chunk[2] })
    end
    table.insert(virt, line)
  end
  vim.api.nvim_buf_set_extmark(buf, M.ns, q.last, 0, { virt_lines = virt })
end

function M.plain(lines, hl)
  local rows = {}
  for i, l in ipairs(lines) do
    rows[i] = { { l, hl } }
  end
  return rows
end

-- The model's language name ("rust", "TypeScript", "c++") if it has a parser,
-- else the buffer's own.
local function ts_lang(name, buf)
  for _, cand in ipairs({ name, vim.bo[buf].filetype }) do
    if cand and cand ~= "" then
      cand = cand:lower()
      local lang = vim.treesitter.language.get_lang(cand) or cand
      local ok, added = pcall(vim.treesitter.language.add, lang)
      if ok and added then
        return lang
      end
    end
  end
end

-- refresh() redraws on every edit, so parse each answer only once.
local memo = {}

-- Treesitter-highlighted rows for a code answer. Falls back to plain ghost
-- text when there's no parser or highlight query for the language.
function M.code(body, lang, buf)
  lang = ts_lang(lang, buf)
  local key = (lang or "") .. "\0" .. body
  if memo[key] then
    return memo[key]
  end
  local lines = vim.split(body, "\n", { plain = true })
  local query = lang and vim.treesitter.query.get(lang, "highlights")
  local ok, parser = pcall(vim.treesitter.get_string_parser, body, lang or "")
  if not (query and ok) then
    memo[key] = M.plain(lines, "GhostText")
    return memo[key]
  end

  -- Captures come in pattern order and later ones win, as in the editor's
  -- own highlighter. Paint them per byte, then merge runs into chunks.
  local paint = {}
  for i = 1, #lines do
    paint[i] = {}
  end
  for id, node in query:iter_captures(parser:parse()[1]:root(), body, 0, -1) do
    local name = query.captures[id]
    if name ~= "spell" and name ~= "nospell" and not vim.startswith(name, "_") then
      local group = "@" .. name .. "." .. lang
      local sr, sc, er, ec = node:range()
      for r = sr, er do
        local len = #(lines[r + 1] or "")
        for c = (r == sr and sc or 0) + 1, (r == er and ec or len) do
          paint[r + 1][c] = group
        end
      end
    end
  end

  local rows = {}
  for i, line in ipairs(lines) do
    local row, run, start = {}, nil, 1
    for c = 1, #line + 1 do
      local group = paint[i][c]
      if c > #line or group ~= run then
        if c > start then
          table.insert(row, { line:sub(start, c - 1), run and { run, "GhostCode" } or "GhostCode" })
        end
        run, start = group, c
      end
    end
    rows[i] = row
  end
  memo[key] = rows
  return rows
end

return M
