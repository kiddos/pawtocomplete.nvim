local api = vim.api
local lsp = vim.lsp

local M = {}

local config = require('pawtocomplete.config').get_config()
local util = require('pawtocomplete.util')
local paw = require('pawtocomplete.paw')
local popup_menu = require('pawtocomplete.completion_menu')

popup_menu.setup()

local context = {
  completion_items = {},
  request_ids = {},
  preview_id = nil,
  ns_id = api.nvim_create_namespace("pawtocomplete"),
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
  local text = item.insertText or item.label
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

  local bufnr = api.nvim_get_current_buf()
  vim.lsp.util.apply_text_edits({ text_edit }, bufnr, 'utf-8')

  local text = paw.table_get(text_edit, { 'newText' })
  local row = paw.table_get(text_edit, { 'range', 'start', 'line' })
  local col = paw.table_get(text_edit, { 'range', 'start', 'character' })
  if text and row and col then
    vim.api.nvim_win_set_cursor(0, { row + 1, col + #text })
  end
end

M.show_completion = function(start)
  local base_word = find_completion_base_word(start + 1)
  if not base_word then
    return
  end
  local pos = api.nvim_win_get_cursor(0)

  local option = {
    keyword = base_word,
    insert_cost = config.completion.insert_cost,
    delete_cost = config.completion.delete_cost,
    substitude_cost = config.completion.substitude_cost,
    max_cost = config.completion.edit_dist,
  }
  -- 0-indexed
  local param = {
    line = pos[1] - 1,
    cursor = pos[2],
    start = start,
  }
  local items = paw.filter_and_sort(context.completion_items, option, param)
  if vim.fn.mode() == 'i' then
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

local function make_completion_request_param(start, client)
  local params = lsp.util.make_position_params()
  local line = api.nvim_get_current_line()
  if start > 1 then
    local triggers = paw.table_get(client, { 'server_capabilities', 'completionProvider', 'triggerCharacters' })
    if triggers then
      local trigger_context = paw.find_trigger_context(triggers, line, start-1)
      if trigger_context then
        params.context = trigger_context
      end
    end
  end
  -- params.position.character = start
  return params
end

local function lsp_completion_request(start, client, bufnr, callback)
  if context.request_ids[client.id] then
    client.cancel_request(context.request_ids[client.id])
    context.request_ids[client.id] = nil
  end

  local params = make_completion_request_param(start, client)
  local result, request_id = client.request('textDocument/completion', params, function(err, client_result, _, _)
    if not err then
      local items = paw.table_get(client_result, { 'items' }) or client_result
      if items then
        callback(items)
      end
    end
  end, bufnr)
  if result then
    context.request_ids[client.id] = request_id
  end
end

M.trigger_completion = util.debounce(function(bufnr)
  local clients = lsp.get_clients({ bufnr = bufnr })
  context.completion_items = {}

  local line = api.nvim_get_current_line()
  local col = api.nvim_win_get_cursor(0)[2]
  local line_to_cursor = line:sub(1, col)

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

  if start >= 0 and start <= col then
    for _, client in pairs(clients) do
      if paw.table_get(client, { 'server_capabilities', 'completionProvider' }) then
        lsp_completion_request(start, client, bufnr, function(items)
          if items then
            for _, item in pairs(items) do
              table.insert(context.completion_items, item)
            end
          end
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
      client.cancel_request(request_id)
      context.request_ids[client_id] = nil
    end
  end
  context.completion_items = {}
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

  api.nvim_set_keymap('i', '<C-Space>', '', {
    expr = true,
    noremap = true,
    callback = M.auto_complete,
  })
end

return M
