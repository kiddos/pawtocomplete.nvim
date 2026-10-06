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

local function find_completion_base_word(start)
  if start <= 0 then
    return nil
  else
    local line = api.nvim_get_current_line()
    local col = api.nvim_win_get_cursor(0)[2]
    return string.sub(line, start, col)
  end
end

local function get_col_from_item(item)
  local keys = { 'range', 'insert', 'replace' }
  for _, key in pairs(keys) do
    local character = paw.table_get(item, { 'textEdit', key, 'start', 'character' })
    if character then
      return character
    end
  end
  return nil
end

local function extmark_at_cursor(item)
  -- local text = item.insertText or item.label
  local text = item.filterText or item.insertText or item.label
  local bufnr = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1]
  local col = get_col_from_item(item)
  print(col)
  if not col then
    return
  end

  if context.preview_id then
    api.nvim_buf_del_extmark(bufnr, context.ns_id, context.preview_id)
    context.preview_id = nil
  end

  context.preview_id = api.nvim_buf_set_extmark(bufnr, context.ns_id, row - 1, col, {
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

local function parse_completion_edit(edit)
  if not edit then
    return nil
  end

  local range = edit.insert or edit.replace or edit.range
  if not range or not range.start then
    return nil
  end

  return {
    range = range,
    line = range.start.line + 1, -- Convert 0-indexed LSP line to 1-indexed Neovim line
    character = range.start.character,
    newText = edit.newText or "",
  }
end

local function apply_text_edit(item)
  local text_edit = paw.table_get(item, { 'textEdit' })
  local parsed = parse_completion_edit(text_edit)
  if not parsed then
    return
  end

  local cursor = api.nvim_win_get_cursor(0)
  if parsed.line ~= cursor[1] then
    return
  end

  local bufnr = api.nvim_get_current_buf()
  local is_snippet = item.insertTextFormat == 2 -- 2 = Snippet format in LSP specs

  if is_snippet then
    local current_line = api.nvim_get_current_line()
    local before = current_line:sub(1, parsed.character)

    api.nvim_set_current_line(before)
    api.nvim_win_set_cursor(0, { parsed.line, parsed.character })

    vim.snippet.expand(parsed.newText)
  else
    local normalized_edit = {
      range = parsed.range,
      newText = parsed.newText,
    }

    lsp.util.apply_text_edits({ normalized_edit }, bufnr, 'utf-8')
    if #parsed.newText > 0 then
      api.nvim_win_set_cursor(0, { parsed.line, parsed.character + #parsed.newText })
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
        if not item.documentation then
          local client = lsp.get_client_by_id(item.clientId)
          if client and paw.table_get(client, { 'server_capabilities', 'completionProvider', 'resolveProvider' }) then
            local handler = function(err, resolved_item)
              if not err and resolved_item then
                item.documentation = resolved_item.documentation
                item.detail = resolved_item.detail or item.detail
                popup_menu.refresh_preview()
              end
            end
            client:request('completionItem/resolve', item, handler, 0)
          end
        end
      end
    })
  end
end

local function lsp_completion_request(client, bufnr, callback)
  if context.request_ids[client.id] then
    client:cancel_request(context.request_ids[client.id])
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

  local result, request_id = client:request('textDocument/completion', params, handler, bufnr)
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
    local s = paw.get_completion_start(client, line_to_cursor)
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
