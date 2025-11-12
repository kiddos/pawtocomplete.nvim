local api = vim.api
local lsp = vim.lsp
local fn = vim.fn

local M = {}

local config = require('pawtocomplete.config').get_config()
local util = require('pawtocomplete.util')
local paw = require('pawtocomplete.paw')

local context = {
  lsp = {
    result = {},
    request_ids = {},
    window = nil,
    buffer = nil,
    text = nil,
  },
}

local function get_left_char()
  local line = api.nvim_get_current_line()
  local col = api.nvim_win_get_cursor(0)[2]
  return string.sub(line, col, col)
end

M.auto_signature = util.debounce(function()
  local bufnr = api.nvim_get_current_buf()
  local clients = lsp.get_clients({ bufnr = bufnr })
  context.lsp.result = {}

  local left_char = get_left_char()
  for _, client in pairs(clients) do
    local triggers = paw.table_get(client, { 'server_capabilities', 'signatureHelpProvider', 'triggerCharacters' }) or {}
    if vim.tbl_contains(triggers, left_char) then
      if paw.table_get(client, { 'server_capabilities', 'signatureHelpProvider' }) then
        if context.lsp.request_ids[client.id] then
          client:cancel_request(context.lsp.request_ids[client.id])
          context.lsp.request_ids[client.id] = nil
        end

        local offset_encoding = client.offset_encoding or 'utf-16'
        local params = lsp.util.make_position_params(0, offset_encoding)
        local result, request_id = client:request('textDocument/signatureHelp', params, function(err, client_result, _, _)
          if not err then
            context.lsp.result[client.id] = client_result
            M.show_signature_window()
          end
        end, bufnr)

        if result then
          context.lsp.request_ids[client.id] = request_id
        end
      end
    end
  end
end, config.signature.delay)

M.get_signature_lines = function()
  local lines = {}
  local docs = {}
  for _, result in pairs(context.lsp.result) do
    local signatures = result.signatures
    if type(signatures) == 'table' then
      for _, signature_help in pairs(signatures) do
        local label = signature_help.label or ''
        local document = signature_help.documentation
        if document and type(document) == 'table' then
          document = document.value or ''
        end
        table.insert(lines, label)
        table.insert(docs, document)
      end
    end
  end
  return lines, docs
end

M.signature_window_options = function()
  local lines = api.nvim_buf_get_lines(context.lsp.buffer, 0, -1, false)
  local height, width = util.floating_dimensions(lines, config.signature.max_height, config.signature.max_width)

  -- Compute position
  local win_line = fn.winline()
  local space_above, space_below = win_line - 1, fn.winheight(0) - win_line

  local anchor = 'NW'
  local row = 1
  local space = space_below
  if height <= space_above or space_below <= space_above then
    anchor, row, space = 'SW', 0, space_above
  end

  -- Possibly adjust floating window dimensions to fit screen
  if space < height then
    height, width = util.floating_dimensions(lines, space, config.signature.max_width)
  end

  -- Get zero-indexed current cursor position
  local bufpos = api.nvim_win_get_cursor(0)
  bufpos[1] = bufpos[1] - 1

  return {
    relative = 'win',
    bufpos = bufpos,
    anchor = anchor,
    row = row,
    col = 0,
    width = width,
    height = height,
    focusable = false,
    style = 'minimal',
    border = 'rounded',
  }
end

local function create_buffer(container, name)
  if container.buffer then
    api.nvim_buf_delete(container.buffer, { force = true })
  end

  container.buffer = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(container.buffer, name)
  api.nvim_set_option_value('buftype', 'nofile', { buf = container.buffer })
end

M.show_signature_window = function()
  if not context.lsp.result then
    return
  end

  local lines, docs = M.get_signature_lines()
  if not lines or paw.is_whitespace(lines) then
    return
  end

  local signatures = {}
  local bufnr = api.nvim_get_current_buf()
  local filetype = api.nvim_get_option_value('filetype', { buf = bufnr })
  table.insert(signatures, string.format('```%s', filetype))
  for _, line in ipairs(lines) do
    table.insert(signatures, line)
  end
  table.insert(signatures, '```')

  if docs and not paw.is_whitespace(docs) then
    table.insert(signatures, '')
    for _, doc in pairs(docs) do
      table.insert(signatures, doc)
    end
  end

  create_buffer(context.lsp, 'function-signature')
  lsp.util.stylize_markdown(context.lsp.buffer, signatures, {})

  local cur_text = table.concat(lines, '\n')
  if context.lsp.window and cur_text == context.lsp.text then
    return
  end

  util.close_action_window(context.lsp)
  context.lsp.text = cur_text
  if fn.mode() == 'i' and #cur_text > 0 then
    local options = M.signature_window_options()
    util.open_action_window(context.lsp, options)
  end
end

M.stop_signature = function()
  util.close_action_window(context.lsp)

  for client_id, request_id in pairs(context.lsp.request_ids) do
    local client = lsp.get_client_by_id(client_id)
    if client and request_id then
      client:cancel_request(request_id)
      context.lsp.request_ids[client_id] = nil
    end
  end

  context.lsp.result = {}
  context.lsp.text = nil
end

M.setup = function()
  api.nvim_create_autocmd({ 'CursorMovedI' }, {
    callback = M.auto_signature
  })

  api.nvim_create_autocmd({ 'InsertLeavePre' }, {
    callback = M.stop_signature
  })
end

return M
