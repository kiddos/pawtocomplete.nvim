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

M.get_signatures = function()
  local signatures = {}
  for _, result in pairs(context.lsp.result) do
    if type(result.signatures) == 'table' then
      for _, sig in pairs(result.signatures) do
        local signature = {
          label = sig.label or '',
          documentation = sig.documentation,
          activeParameter = sig.activeParameter or result.activeParameter or 0,
          parameters = sig.parameters or {},
        }
        if type(signature.documentation) == 'table' then
          signature.documentation = signature.documentation.value or ''
        end
        table.insert(signatures, signature)
      end
    end
  end
  return signatures
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

M.show_signature_window = util.debounce(function()
  if not context.lsp.result then
    return
  end

  local sigs = M.get_signatures()
  if #sigs == 0 then
    return
  end

  local markdown_lines = {}
  local bufnr = api.nvim_get_current_buf()
  local filetype = api.nvim_get_option_value('filetype', { buf = bufnr })
  table.insert(markdown_lines, string.format('```%s', filetype))
  for _, sig in ipairs(sigs) do
    table.insert(markdown_lines, sig.label)
  end
  table.insert(markdown_lines, '```')

  for _, sig in ipairs(sigs) do
    if sig.documentation and #sig.documentation > 0 then
      table.insert(markdown_lines, '')
      table.insert(markdown_lines, sig.documentation)
    end
  end

  local cur_text = table.concat(markdown_lines, '\n')
  if context.lsp.window and cur_text == context.lsp.text then
    return
  end

  create_buffer(context.lsp, 'function-signature')
  lsp.util.stylize_markdown(context.lsp.buffer, markdown_lines, {})

  -- Highlight active parameters
  -- The signatures start after the first match of ``` language
  -- Usually line 2 (index 1)
  local ns_id = api.nvim_create_namespace('pawtocomplete.signature_hl')
  for i, sig in ipairs(sigs) do
    local active_param_idx = sig.activeParameter
    local params = sig.parameters
    if params and params[active_param_idx + 1] then
      local param = params[active_param_idx + 1]
      local label = param.label
      local start_col, end_col

      if type(label) == 'table' then
        start_col, end_col = label[1], label[2]
      elseif type(label) == 'string' then
        start_col, end_col = sig.label:find(label, 1, true)
        if start_col then
          start_col = start_col - 1 -- 0-indexed
        end
      end

      if start_col and end_col then
        api.nvim_buf_add_highlight(context.lsp.buffer, ns_id, 'LspSignatureActiveParameter', i, start_col, end_col)
      end
    end
  end

  context.lsp.text = cur_text
  if fn.mode() == 'i' and #cur_text > 0 then
    local options = M.signature_window_options()
    util.open_action_window(context.lsp, options)
  end
end, config.signature.delay)

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
