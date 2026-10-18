-- Runs one question through an AI CLI, using whatever login that CLI already
-- has. Each adapter turns (prompt, system, opts) into an argv plus a parser
-- for its output; the parser returns the decoded { kind, lang, body } table.
local M = {}

local schema = {
  type = "object",
  properties = {
    kind = { type = "string", enum = { "code", "steps" } },
    lang = { type = "string" },
    body = { type = "string" },
  },
  -- Codex's structured output requires every property to be required.
  required = { "kind", "lang", "body" },
  additionalProperties = false,
}

local function read_file(p)
  local f = io.open(p, "r")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

local function first_line(s)
  s = vim.trim(s or "")
  return s ~= "" and s:match("[^\n]+") or nil
end

-- The outermost {...} in free-form output, for CLIs without a schema flag.
local function decode_loose(s)
  local json = (s or ""):match("%b{}")
  local ok, out = pcall(vim.json.decode, json or "")
  return ok and type(out) == "table" and out or nil
end

-- Backends without a separate system prompt get it inlined, along with the
-- shape of the answer.
local function inline(prompt, system)
  return table.concat({
    system,
    'Reply with only a JSON object: {"kind": "code" | "steps", "lang": "<language or empty>", "body": "<the answer>"}. Answer directly; do not run commands or read files.',
    "",
    prompt,
  }, "\n")
end

M.adapters = {}

-- Everything optional is stripped (tools, MCP servers, skills, settings) so a
-- call carries ~2k tokens of overhead instead of ~50k.
function M.adapters.claude(prompt, system, opts)
  -- stylua: ignore
  local argv = {
    opts.cmd or "claude", "-p",
    "--model", opts.model or "sonnet",
    "--output-format", "json",
    "--json-schema", vim.json.encode(schema),
    "--system-prompt", system,
    "--tools", "",
    "--no-session-persistence",
    "--strict-mcp-config",
    "--disable-slash-commands",
    "--setting-sources", "",
  }
  if opts.effort then
    vim.list_extend(argv, { "--effort", opts.effort })
  end
  vim.list_extend(argv, opts.args or {})
  return argv,
    prompt,
    function(res)
      local ok, out = pcall(vim.json.decode, res.stdout or "")
      if not ok or type(out) ~= "table" then
        return nil, first_line(res.stderr) or first_line(res.stdout)
      end
      if out.is_error or type(out.structured_output) ~= "table" then
        return nil, first_line(tostring(out.result or ""))
      end
      return out.structured_output
    end
end

-- Read-only sandbox, nothing saved. The schema and the final message go
-- through temp files, since `codex exec` streams progress on stdout/stderr.
function M.adapters.codex(prompt, system, opts)
  local schema_file, answer_file = vim.fn.tempname(), vim.fn.tempname()
  local f = assert(io.open(schema_file, "w"))
  f:write(vim.json.encode(schema))
  f:close()
  -- stylua: ignore
  local argv = {
    opts.cmd or "codex", "exec",
    "--sandbox", "read-only",
    "--skip-git-repo-check",
    "--ephemeral",
    "--color", "never",
    "--output-schema", schema_file,
    "--output-last-message", answer_file,
  }
  if opts.model then
    vim.list_extend(argv, { "--model", opts.model })
  end
  if opts.effort then
    vim.list_extend(argv, { "-c", ("model_reasoning_effort=%q"):format(opts.effort) })
  end
  vim.list_extend(argv, opts.args or {})
  table.insert(argv, "-")
  return argv,
    inline(prompt, system),
    function(res)
      local answer = decode_loose(read_file(answer_file))
      os.remove(schema_file)
      os.remove(answer_file)
      if not answer then
        return nil, first_line(res.stderr) or ("codex exited " .. res.code)
      end
      return answer
    end
end

-- Any other CLI: `backend = { cmd = { "my-llm", "--flag" } }`. It gets the
-- whole prompt on stdin and must print the JSON answer somewhere on stdout.
local function custom(spec)
  return function(prompt, system)
    return vim.deepcopy(spec.cmd),
      inline(prompt, system),
      function(res)
        local answer = decode_loose(res.stdout)
        if not answer then
          return nil, first_line(res.stderr) or "no JSON answer on stdout"
        end
        return answer
      end
  end
end

-- cb(answer, err) runs on the main loop. answer = { kind, lang, body }.
-- opts: backend, cmd, model, effort, args, timeout_ms, cwd.
function M.ask(prompt, system, opts, cb)
  local adapter = type(opts.backend) == "table" and custom(opts.backend) or M.adapters[opts.backend]
  if not adapter then
    return cb(nil, ("unknown backend %q"):format(tostring(opts.backend)))
  end
  local argv, stdin, parse = adapter(prompt, system, opts)
  if vim.fn.executable(argv[1]) == 0 then
    return cb(nil, argv[1] .. " not found (see :checkhealth ghost)")
  end
  vim.system(
    argv,
    { stdin = stdin, text = true, timeout = opts.timeout_ms, cwd = opts.cwd },
    vim.schedule_wrap(function(res)
      if res.code == 124 then
        return cb(nil, ("timed out after %ds"):format(opts.timeout_ms / 1000))
      end
      local ans, err = parse(res)
      if not ans or type(ans.body) ~= "string" then
        return cb(nil, err or (argv[1] .. " exited " .. res.code))
      end
      cb(ans)
    end)
  )
end

-- The executable a backend will run, for :checkhealth.
function M.executable(opts)
  if type(opts.backend) == "table" then
    return opts.backend.cmd[1]
  end
  return opts.cmd or opts.backend
end

return M
