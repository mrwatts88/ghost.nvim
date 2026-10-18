-- Finds `?` questions: a comment line whose text starts with "?", plus any
-- plain comment lines directly below it, so a long question can wrap.
local M = {}

-- Longest first, so "<!--" is tried before shorter leaders.
local leaders = { "<!--", "//", "--", "/*", "#", ";", "%", "*" }

-- Closers go first, so a bare "-->" or "*/" line isn't read as a "--" or "*"
-- comment with text in it.
local function strip_closers(s)
  return vim.trim((s:gsub("%*/%s*$", ""):gsub("%-%->%s*$", "")))
end

-- The text of a comment line without its leader, or nil if it isn't one.
local function comment_text(line)
  local s = strip_closers(vim.trim(line))
  for _, l in ipairs(leaders) do
    if vim.startswith(s, l) then
      return vim.trim(s:sub(#l + 1))
    end
  end
end

-- Treesitter's view, when the buffer has a parser: nil if the line only looks
-- like a comment (e.g. inside a string), else the row the comment ends on,
-- which is past `row` for a multi-line block comment.
local function comment_end(buf, row, col)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
  if not ok or not node then
    return row
  end
  local t = node:type()
  -- Markdown parses <!-- --> as an html_block.
  if not (t:find("comment") or t == "html_block") then
    return nil
  end
  local _, _, end_row, end_col = node:range()
  if end_col == 0 then
    end_row = end_row - 1
  end
  return math.max(end_row, row)
end

function M.scan(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out = {}
  local i = 1
  while i <= #lines do
    local text = comment_text(lines[i])
    local indent = lines[i]:match("^%s*")
    local stop = text and text:sub(1, 1) == "?" and comment_end(buf, i - 1, #indent)
    if stop then
      local parts = { vim.trim(text:sub(2)) }
      local j = i
      if stop > i - 1 then
        -- Block comment: the whole comment is the question.
        for r = i + 1, stop + 1 do
          local l = strip_closers(vim.trim(lines[r])):gsub("^%*%s*", "")
          if l ~= "" then
            table.insert(parts, l)
          end
        end
        j = stop + 1
      else
        -- Line comments: keep reading plain comment lines below.
        while j < #lines do
          local nxt = comment_text(lines[j + 1])
          if not nxt or nxt == "" or nxt:sub(1, 1) == "?" then
            break
          end
          table.insert(parts, nxt)
          j = j + 1
        end
      end
      local question = vim.trim(table.concat(parts, " "):gsub("%s+", " "))
      if question ~= "" then
        table.insert(out, {
          question = question,
          -- Keyed by the question's text, never its line, so answers follow
          -- the comment when it moves.
          key = vim.fn.sha256(question):sub(1, 12),
          first = i - 1,
          last = j - 1,
          indent = indent,
        })
      end
      i = j + 1
    else
      i = i + 1
    end
  end
  return out
end

function M.at_cursor(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  for _, q in ipairs(M.scan(buf)) do
    if row >= q.first and row <= q.last then
      return q
    end
  end
end

return M
