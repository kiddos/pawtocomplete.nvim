local api = vim.api
local lsp = vim.lsp
local fn = vim.fn

local M = {}

local config = require('pawtocomplete.config').get_config()
local util = require('pawtocomplete.util')
local paw = require('pawtocomplete.paw')
local popup_menu = require('pawtocomplete.completion_menu')

popup_menu.setup()

local context = {
  request_ids = {},
  preview_id = nil,
  ns_id = api.nvim_create_namespace("pawtocomplete.completion"),
}

local function get_completion_start(client, line_to_cursor)
  local start = -1
  local triggers = paw.table_get(client, { 'server_capabilities', 'completionProvider', 'triggerCharacters' })
  if triggers then
    for _, trigger_char in pairs(triggers) do
      local result = paw.find_last_trigger_index(line_to_cursor, trigger_char)
      if result ~= nil then
        -- the result is 0-index based
        -- completion should trigger at trigger character + 1
        start = math.max(start, result + 1)
      end
    end
  end
  return start
end

local function find_completion_base_word(start)
  if start <= 0 then
    return nil
  else
    local line = api.nvim_get_current_line()
    local col = api.nvim_win_get_cursor(0)[2]
    return string.sub(line, start, col)
  end
end

local function extmark_at_cursor(item)
  -- local text = item.insertText or item.label
  local text = item.filterText or item.insertText or item.label
  local character = paw.table_get(item, { 'textEdit', 'range', 'start', 'character' })
  local bufnr = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1]

  if context.preview_id then
    api.nvim_buf_del_extmark(bufnr, context.ns_id, context.preview_id)
    context.preview_id = nil
  end

  context.preview_id = api.nvim_buf_set_extmark(bufnr, context.ns_id, row - 1, character, {
    virt_text = { { text, "Normal" } },
    virt_text_pos = 'overlay',
    priority = 10,
  })

  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertLeavePre' }, {
    buffer = bufnr,
    callback = function()
      if context.preview_id then
        api.nvim_buf_del_extmark(bufnr, context.ns_id, context.preview_id)
        context.preview_id = nil
        api.nvim_command('redraw')
      end
    end,
    once = true,
  })
end

local function apply_text_edit(item)
  local text_edit = paw.table_get(item, { 'textEdit' })
  if not text_edit then
    return
  end

  local character = paw.table_get(text_edit, { 'range', 'start', 'character' })
  local line = paw.table_get(text_edit, { 'range', 'start', 'line' }) + 1
  local cursor = api.nvim_win_get_cursor(0)
  if line ~= cursor[1] then
    return
  end

  local bufnr = api.nvim_get_current_buf()
  if item.insertTextFormat == 2 then
    local current_line = api.nvim_get_current_line()
    local before = current_line:sub(1, character)
    api.nvim_set_current_line(before)
    api.nvim_win_set_cursor(0, { line, character })

    local snippet = paw.table_get(text_edit, { 'newText' })
    vim.snippet.expand(snippet)
  else
    lsp.util.apply_text_edits({ text_edit }, bufnr, 'utf-8')
    local text = paw.table_get(text_edit, { 'newText' })
    if text then
      api.nvim_win_set_cursor(0, { line, character + #text })
    end
  end
end

M.show_completion = function(start)
  local base_word = find_completion_base_word(start + 1)
  if not base_word then
    base_word = ''
  end
  local pos = api.nvim_win_get_cursor(0)

  local option = {
    keyword = base_word,
    insert_cost = config.completion.insert_cost,
    delete_cost = config.completion.delete_cost,
    substitude_cost = config.completion.substitude_cost,
    max_cost = config.completion.max_cost,
  }
  local bufnr = api.nvim_get_current_buf()
  local items = paw.get_completion_items(bufnr, pos[1], pos[2], start + 1, option)
  if fn.mode() == 'i' and #items > 0 then
    paw.interact()
    popup_menu.open(items, {
      on_select = function(selected_item, _)
        apply_text_edit(selected_item)
      end,
      on_preview = function(item, _)
        extmark_at_cursor(item)
      end
    })
  end
end

local function lsp_completion_request(client, bufnr, callback)
  if context.request_ids[client.id] then
    client.cancel_request(context.request_ids[client.id])
    context.request_ids[client.id] = nil
  end

  local offset_encoding = client.offset_encoding or 'utf-16'
  local params = lsp.util.make_position_params(0, offset_encoding)
  local handler = function(err, client_result, _)
    if not err then
      local items = paw.table_get(client_result, { 'items' }) or client_result
      if items then
        callback(items)
      end
    end
  end

  local result, request_id = client.request('textDocument/completion', params, handler, bufnr)
  if result then
    context.request_ids[client.id] = request_id
  end
end

local function can_trigger_completion(bufnr)
  local valid = api.nvim_buf_is_valid(bufnr)
  if not valid then
    return false
  end

  local modifiable = api.nvim_get_option_value('modifiable', { buf = bufnr })
  if not modifiable then
    return false
  end

  local buftype = api.nvim_get_option_value('buftype', { buf = bufnr })
  if buftype == 'nofile' or buftype == 'prompt' or buftype == 'terminal' then
    return false
  end

  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    return false
  end
  return true
end

M.trigger_completion = util.debounce(function(bufnr)
  if not can_trigger_completion(bufnr) then
    return
  end

  local clients = lsp.get_clients({ bufnr = bufnr })

  local current_line = api.nvim_get_current_line()
  local cursor = api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]
  local line_to_cursor = current_line:sub(1, col)

  local start = -1
  for _, client in pairs(clients) do
    local s = get_completion_start(client, line_to_cursor)
    start = math.max(start, s)
  end

  local result = paw.find_last_word_index(line_to_cursor)
  if result ~= nil then
    -- the result is 0-index based
    start = math.max(start, result)
  end

  popup_menu.close()
  -- if paw.has_cache(bufnr, line, col) then
  --   M.show_completion(start)
  -- end
  paw.clear_completion_items()

  if start >= 0 and start <= col then
    for _, client in pairs(clients) do
      if paw.table_get(client, { 'server_capabilities', 'completionProvider' }) then
        lsp_completion_request(client, bufnr, function(items)
          paw.insert_items(items, client.id, bufnr, line, col)
          M.show_completion(start)
        end)
      end
    end
  end
end, config.completion.delay)

M.stop_completion = function()
  for client_id, request_id in pairs(context.request_ids) do
    local client = lsp.get_client_by_id(client_id)
    if client and request_id then
      client:cancel_request(request_id)
      context.request_ids[client_id] = nil
    end
  end
  paw.clear_completion_items()
end

M.auto_complete = function()
  local bufnr = api.nvim_get_current_buf()
  M.trigger_completion(bufnr)
end

M.setup = function()
  api.nvim_create_autocmd({ 'InsertCharPre' }, {
    callback = M.auto_complete
  })

  api.nvim_create_autocmd({ 'InsertLeavePre' }, {
    callback = function()
      M.stop_completion()
    end
  })

  api.nvim_create_autocmd({ 'BufWritePost' }, {
    callback = function()
      paw.clear_completion_items()
    end
  })

  api.nvim_set_keymap('i', '<C-Space>', '', {
    expr = true,
    noremap = true,
    callback = M.auto_complete,
  })
end

return M
