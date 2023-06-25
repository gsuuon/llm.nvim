-- All positions should be 0-indexed

local M = {}

function M.noop() end

local function show(item, level, opt)
  local _body = type(item) == 'string' and item or vim.inspect(item)
  local _level = level or vim.log.levels.INFO

  local _opt =
    opt == nil and {} or
    type(opt) == 'string' and { title = opt } or
    opt

  vim.notify(_body, _level, _opt)
end

function M.show(item, opt)
  show(item, vim.log.levels.INFO, opt)
end

function M.eshow(item, opt)
  if type(item) == 'table' and item.message ~= nil and item.stack ~= nil then
    show(
      item.message .. '\n' .. item.stack,
      vim.log.levels.ERROR,
      opt
    )
  else
    show(
      item,
      vim.log.levels.ERROR,
      opt
    )
  end
end

function M.tap(x, opt)
  M.show(x, opt)
  return x
end

function M.env(name)
  local value = os.getenv(name)

  if value == nil then
    error('Missing environment variable: ' .. name)
  else
    return value
  end
end

function M.memo(fn)
  local cache = {}

  return function(x)
    if cache[x] == nil then
      cache[x] = fn(x)
    end

    return cache[x]
  end
end

function M.queue(size)
  local items = {}

  return {
    add = function(item)
      if #items >= size then
        table.remove(items, 1)
      end

      table.insert(items, item)
    end,
    get = function(idx)
      return items[idx]
    end,
    items = items
  }
end

--- Coroutine wrapper to avoid deeply nested callbacks. Provide `resolve` as the callback fn,
--- and use `wait` to wait for the callback to be called. Optionally provide a callback for the
--- return value of the corouting. Usage example:
---   util.async(function(wait, resolve)
---    local a = wait(callback_a(arg_a, resolve))
---    local b = wait(callback_b(a, resolve))
---    return b
---   end, outer_callback)
--- @param fn fun(wait: (fun(any): any), resolve: (fun(any): any)): any))
--- @param callback? fun(result: any)
function M.async(fn, callback)
  local co = coroutine.create(fn)

  local function wait(cb_fn)
    return coroutine.yield(cb_fn)
  end

  local function resolve(result)
    local success, yield_result = coroutine.resume(co, result)

    if not success then
      error(yield_result)
    end

    if coroutine.status(co) == 'dead' and callback ~= nil then
      callback(yield_result)
    end
  end

  coroutine.resume(co, wait, resolve)
end

M.env_memo = M.memo(M.env)

M.table = {}

function M.table.map_to_array(table, fn)
  local result = {}
  local idx = 1

  for k,v in pairs(table) do
    result[idx] = fn(k, v)
    idx = idx + 1
  end

  return result
end

-- Gets the 0-indexed subslice of a list table
function M.table.slice(tbl, start, stop)
  local function idx(x)
    if x >= 0 then
      return x
    else
      return #tbl + x
    end
  end

  local start_idx = start == nil and 0 or idx(start)
  local stop_idx = stop == nil and #tbl or idx(stop)

  if stop_idx < start_idx then
    error('stop (' .. stop_idx .. ') is less than start (' .. start_idx .. ')')
  end

  local results = {}

  for i = start_idx + 1, stop_idx do
    table.insert(results, tbl[i])
  end

  return results
end

M.json = {}

function M.json.decode(string)
  local success, obj = pcall(vim.json.decode, string, {
    -- obj is error message if not success
    luanil = {
      object = true,
      array = true
    }
  })

  if success then
    return obj
  else
    return nil, obj
  end
end

M.string = {}

-- TODO remove this and just use vim.fn.split
function M.string.split_char(text, sep)
  local res = {}

  local _cur = ''

  for i = 1, #text do
    local char = text:sub(i, i)

    if char == sep then
      table.insert(res, _cur)
      _cur = ''
    else
      _cur = _cur .. char
    end
  end

  table.insert(res, _cur)

  return res
end

function M.string.split_pattern(text, pattern)
  -- gpt made this

  local parts = {}
  local start_index = 1

  repeat
    local end_index = string.find(text, pattern, start_index)

    if end_index == nil then
      end_index = #text + 1
    end

    local part = string.sub(text, start_index, end_index - 1)

    table.insert(parts, part)
    start_index = end_index + #pattern

  until start_index > #text

  return parts
end

function M.string.join_lines(lines)
  return table.concat(lines, '\n')
end

--- Removes any surrounding quotes or markdown code blocks
function M.string.trim_quotes(text)
  local open_markers = text:match([=[^['"`]+]=])

  if open_markers == nil then return text end

  local open = "^" .. open_markers
  local close = open_markers .. "$"

  local result = text:gsub(open, ''):gsub(close, '')

  return result
end

--- Trim markdown code block fence and surrounding quotes
function M.string.trim_code_block(text)
  -- TODO there's probably a simpler way to preserve the surrounding newline semantics
  -- or maybe I don't need is_multiline at all, assume single line blocks are always single backtick
  -- so ```'s always include newlines
  local is_code_block = text:match("^```") and text:match("```$")

  if not is_code_block then return text end

  local has_fence = text:match("^```[^\n]+\n")

  if has_fence then
    local result = text:gsub("^```[^\n]*\n", ''):gsub("\n?```$", '')
    return result
  end

  local is_multiline = text:match("^```\n") and text:match("\n```$")

  if is_multiline then
    local result = text:gsub("^```\n", ''):gsub("\n```$", '')
    return result
  end

  local result = text:gsub("^```", ''):gsub("```$", '')
  return result
end

-- Extracts markdown code blocks and interspliced explanations into a list of either
-- {code: string, lang: string} or {text: string}
function M.string.extract_markdown_code_blocks(md_text)
  local blocks = {}
  local current_block = { text = "" }
  local in_code_block = false

  local function add_text_block()
    if current_block.text ~= nil and #current_block.text > 0 then
      table.insert(blocks, current_block)
    end
  end

  for line in md_text:gmatch("[^\r\n]+") do
    local code_fence = line:match("^```([%w-]*)")
    if code_fence then
      in_code_block = not in_code_block
      if in_code_block then
        add_text_block()
        current_block = { code = "", lang = code_fence }
      else
        table.insert(blocks, current_block)
        current_block = { text = "" }
      end
    elseif in_code_block then
      current_block.code = current_block.code .. line .. "\n"
    else
      current_block.text = current_block.text .. line .. "\n"
    end
  end

  add_text_block()
  return blocks
end

M.cursor = {}

function M.cursor.selection()
  local start = vim.fn.getpos("'<")
  local stop = vim.fn.getpos("'>")

  return {
    start = {
      row = start[2] - 1,
      col = start[3] - 1
    },
    stop = {
      row = stop[2] - 1,
      col = stop[3] -- stop col can be vim.v.maxcol which means entire line
    }
  }
end

function M.cursor.position()
  local pos = vim.api.nvim_win_get_cursor(0)

  return {
    row = pos[1] - 1,
    col = pos[2]
  }
end

function M.cursor.place_with_keys(position)
  local keys = position.row + 1 .. 'G0'

  if position.col > 0 then
    keys = keys .. position.col .. 'l'
  end

  return keys
end

M.position = {}

-- b is less than a
function M.position.is_less(a, b)
  if a.row == b.row then
    return b.col < a.col
  end

  return b.row < a.row
end

-- b is greater or equal to a
function M.position.is_greater_eq(a, b)
  return not M.position.is_less(a, b)
end

-- pos is between start (inclusive) and final (exclusive)
-- false if pos == start == final
function M.position.is_bounded(pos, start, stop)
  return M.position.is_greater_eq(start, pos) and M.position.is_less(stop, pos)
end

M.COL_ENTIRE_LINE = vim.v.maxcol or 2147483647

M.buf = {}

function M.buf.text(selection)
  local start_row = selection.start.row
  local start_col = selection.start.col

  if start_col == M.COL_ENTIRE_LINE then
    start_row = start_row + 1
    start_col = 0
  end

  return vim.api.nvim_buf_get_text(
    0,
    start_row,
    start_col,
    selection.stop.row,
    selection.stop.col == M.COL_ENTIRE_LINE and -1 or selection.stop.col,
    {}
  )
end

function M.buf.set_text(selection, lines)
  local stop_col =
    selection.stop.col == M.COL_ENTIRE_LINE
      and #assert(
            vim.api.nvim_buf_get_lines(0, selection.stop.row, selection.stop.row + 1, true)[1],
            'No line at ' .. tostring(selection.stop.row)
          )
      or selection.stop.col

  vim.api.nvim_buf_set_text(
    0,
    selection.start.row,
    selection.start.col,
    selection.stop.row,
    stop_col,
    lines
  )
end

function M.buf.filename()
  return vim.fs.normalize(vim.fn.expand('%:.'))
end

---@param callback fun(user_input: string, prompt_content: string)
---@param initial_content? string | string[]
---@param title? string
function M.buf.prompt(callback, initial_content, title)
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'prompt')

  vim.cmd(':b ' .. bufnr)

  vim.api.nvim_set_option_value('winbar', title or 'Prompt', { scope = 'local' })

  if initial_content ~= nil then
    if type(initial_content) == "string" then
      initial_content = vim.fn.split(initial_content, '\n')
    end
    vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, initial_content)
  end

  vim.fn.prompt_setcallback(bufnr, function(user_input)
    local buf_content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -3, false), '\n')
    local success, result = pcall(callback, user_input, buf_content)

    if not success then
      vim.notify(result, vim.log.levels.ERROR)
    end

    vim.cmd(':bd! ' .. bufnr)
  end)

  vim.cmd.startinsert()
end

M.module = {}

--- Re-require a module on access. Useful when developing a prompt library to avoid restarting nvim.
--- Plenty of gotchas here (need special function for pairs, perf is bad) so shouldn't be used always
function M.module.autoload(package_name)
  local mod = {}

  local stale = true

  local function load()
    if stale then
      package.loaded[package_name] = nil

      stale = false

      vim.defer_fn(function()
        stale = true
      end, 1)
    end

    return require(package_name)
  end

  setmetatable(mod, {
    __index = function(_, key)
      return load()[key]
    end,
  })

  mod.__autopairs = function()
    return pairs(load())
  end

  return mod
end

--- Pairs for autoloaded modules. Safe to use on all tables.
--- __pairs metamethod isn't available in Lua 5.1
function M.module.autopairs(table)
  if table.__autopairs ~= nil then
    return table.__autopairs()
  end

  return pairs(table)
end

M.builder = {}

function M.builder.user_prompt(callback, input, title)
  return function(resolve)
    M.buf.prompt(function(user_input, buffer_content)
      resolve(callback(user_input, buffer_content))
    end, input, title)
  end
end

return M
