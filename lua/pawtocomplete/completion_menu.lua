local api = vim.api
local lsp = vim.lsp
local paw = require('pawtocomplete.paw')

local M = {}

local default_config = {
  keymap = {
    up = '<C-p>',
    down = '<C-n>',
    select = '<CR>',
    close = '<C-e>'
  },
  window = {
    width = 60,
    max_width = 80,
    max_height = 10,
    relative = 'cursor',
    style = 'minimal',
    border = 'none',
    zindex = 50,
    row = 1,
    col = 0
  },
  item_defaults = {
    kind = 1,
    label = '',
    detail = '',
  }
}

local context = {
  config = default_config,
  buf = nil,
  win = nil,
  preview_buf = nil,
  preview_win = nil,
  items = {},
  selected_idx = 1,
  on_select = nil,
  on_preview = nil,
}


local function create_popup()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
  api.nvim_set_option_value('filetype', 'PopupMenu', { buf = buf })

  local config = context.config
  local num_items = #context.items
  local height = math.min(num_items, config.window.max_height)

  local content_width = config.window.width or 60
  local content_height = height
  for _, item in ipairs(context.items) do
    local item_width = math.min(#item.label + 3, config.window.max_width)
    content_width = math.max(content_width, item_width)
  end
  local win_width = api.nvim_win_get_width(0)
  local win_height = api.nvim_win_get_height(0)
  local pos = api.nvim_win_get_cursor(0)
  local col = config.window.col
  if pos[2] + content_width > win_width then
    col = win_width - content_width
  end
  local row = config.window.row
  if pos[1] + content_height > win_height then
    row = - content_height - 1
  end

  local win = api.nvim_open_win(buf, false, {
    relative = config.window.relative,
    row = row,
    col = col,
    width = content_width,
    height = content_height,
    style = config.window.style,
    border = config.window.border,
    zindex = config.window.zindex
  })

  -- Set window options similar to completion popup
  api.nvim_set_option_value('winhl', 'Normal:Pmenu,CursorLine:PmenuSel,FloatBorder:PmenuBorder', { win = win })
  api.nvim_set_option_value('cursorline', true, { win = win })
  api.nvim_set_option_value('scrolloff', 0, { win = win })
  api.nvim_set_option_value('sidescrolloff', 0, { win = win })

  -- Ensure no line numbers etc.
  api.nvim_set_option_value('number', false, { win = win })
  api.nvim_set_option_value('relativenumber', false, { win = win })
  api.nvim_set_option_value('signcolumn', 'no', { win = win })
  api.nvim_set_option_value('foldenable', false, { win = win })
  return buf, win
end

local function create_preview_window(_)
  if context.preview_win and api.nvim_win_is_valid(context.preview_win) then
    api.nvim_win_close(context.preview_win, true)
  end

  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  api.nvim_set_option_value('buftype', 'nofile', { buf = buf })

  local total = #context.items
  local current_selected = context.selected_idx
  local emoji = paw.cat_emoji() or '🐱'
  local stars = paw.get_stars(context.items[current_selected].cost)
  local info = string.format(' %s  %d/%d %s', emoji, current_selected, total, stars)
  local lines = {info}
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Calculate position (above or below the main popup)
  local popup_height = api.nvim_win_get_height(context.win)
  local popup_width = api.nvim_win_get_width(context.win)
  local doc_height = math.min(#lines, 3)
  local doc_width = popup_width
  local row = popup_height

  local win = api.nvim_open_win(buf, false, {
    relative = 'win',
    win = context.win,
    row = row,
    col = 0,
    width = doc_width,
    height = doc_height,
    style = 'minimal',
    border = 'none',
    zindex = context.config.window.zindex - 1
  })
  api.nvim_set_option_value('winhl', 'Normal:Pmenu,FloatBorder:PmenuBorder', { win = win })

  context.preview_win = win
  context.preview_buf = buf
end

local hl_groups = {
  'Normal', -- Text
  'Function', -- Method
  'Function', -- Function
  'Type', -- Constructor
  'Identifier', -- Field
  'Identifier', -- Variable
  'Type', -- Class
  'Type', -- Interface
  'SpecialChar', -- Module
  'SpecialChar', -- Property
  'Constant', -- Unit
  'Constant', -- Value
  'Constant', -- Enum
  'Keyword', -- Keyword
  'Function', -- Snippet
  'Constant', -- Color
  'Tag', -- File
  'Tag', -- Reference
  'Tag', -- Folder
  'Constant', -- EnumMember
  'Constant', -- Constant
  'Keyword', -- Struct
  'Normal', -- Event
  'Normal', -- Operator
  'Type', -- TypeParameter
}

local function render_menu()
  local lines = {}
  local hl_commands = {}

  for i, item in ipairs(context.items) do
    table.insert(lines, string.format(' %s  %s', lsp.protocol.CompletionItemKind[item.kind],  item.label))
    table.insert(hl_commands, {
      group = hl_groups[item.kind],
      line = i - 1,
      col_start = 0,
      col_end = 2
    })
  end

  api.nvim_buf_set_lines(context.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(context.buf, -1, 0, -1)

  for _, hl in ipairs(hl_commands) do
    api.nvim_buf_add_highlight(
      context.buf,
      -1,
      hl.group,
      hl.line,
      hl.col_start,
      hl.col_end
    )
  end

  api.nvim_win_set_cursor(context.win, { context.selected_idx, 0 })

  if context.items ~= nil then
    local current_item = context.items[context.selected_idx]
    if current_item then
      create_preview_window(current_item)
    end
  end
end

local function select_item(idx)
  if idx < 1 then
    idx = #context.items
  elseif idx > #context.items then
    idx = 1
  end

  if context.items[idx] and (context.items[idx].type == 'separator' or context.items[idx].type == 'title') then
    if idx > context.selected_idx then
      return select_item(idx + 1)
    else
      return select_item(idx - 1)
    end
  end

  if context.on_preview and context.items[idx] then
    vim.schedule(function()
      context.on_preview(context.items[idx], idx)
    end)
  end

  context.selected_idx = idx
  vim.schedule(function()
    render_menu()
  end)
end

local function move_up()
  select_item(context.selected_idx - 1)
end

local function move_down()
  select_item(context.selected_idx + 1)
end

local function handle_select()
  local selected_item = context.items[context.selected_idx]

  vim.schedule(function()
    M.close()
    if context.on_select and selected_item and selected_item.type ~= 'separator' and selected_item.type ~= 'title' then
      context.on_select(selected_item, context.selected_idx)
    end
  end)
end

local function setup_keymaps()
  local current_buf = api.nvim_get_current_buf()

  local config = context.config
  api.nvim_buf_set_keymap(current_buf, 'i', config.keymap.up, '', {
    noremap = true,
    silent = true,
    callback = function()
      if context.win and api.nvim_win_is_valid(context.win) then
        move_up()
        return ''
      else
        return api.nvim_replace_termcodes('<C-p>', true, true, true)
      end
    end,
    expr = true
  })

  api.nvim_buf_set_keymap(current_buf, 'i', config.keymap.down, '', {
    noremap = true,
    silent = true,
    callback = function()
      if context.win and api.nvim_win_is_valid(context.win) then
        move_down()
        return ''
      else
        return api.nvim_replace_termcodes('<C-n>', true, true, true)
      end
    end,
    expr = true
  })

  api.nvim_buf_set_keymap(current_buf, 'i', config.keymap.select, '', {
    noremap = true,
    silent = true,
    callback = function()
      if context.win and api.nvim_win_is_valid(context.win) then
        handle_select()
        return ''
      else
        return api.nvim_replace_termcodes('<CR>', true, true, true)
      end
    end,
    expr = true
  })

  api.nvim_buf_set_keymap(current_buf, 'i', config.keymap.close, '', {
    noremap = true,
    silent = true,
    callback = function()
      if context.win and api.nvim_win_is_valid(context.win) then
        vim.schedule(function()
          M.close()
        end)
        return ''
      else
        return api.nvim_replace_termcodes('<C-e>', true, true, true)
      end
    end,
    expr = true
  })

  context.source_buf = current_buf
end

local function cleanup_keymaps()
  if context.source_buf and api.nvim_buf_is_valid(context.source_buf) then
    pcall(api.nvim_buf_del_keymap, context.source_buf, 'i', context.config.keymap.up)
    pcall(api.nvim_buf_del_keymap, context.source_buf, 'i', context.config.keymap.down)
    pcall(api.nvim_buf_del_keymap, context.source_buf, 'i', context.config.keymap.select)
    pcall(api.nvim_buf_del_keymap, context.source_buf, 'i', context.config.keymap.close)
  end
end

local function setup_autocommands()
  local group = api.nvim_create_augroup('PopupMenu', { clear = true })

  api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertLeave' }, {
    group = group,
    buffer = context.source_buf,
    callback = function()
      if context.win and api.nvim_win_is_valid(context.win) then
        vim.schedule(function()
          M.close()
        end)
      end
    end
  })
end

function M.open(items, opt)
  M.close()

  if #items == 0 then
    return
  end

  local config = vim.tbl_deep_extend('force', {}, default_config, opt.config or {})
  context.items = items
  context.on_select = opt.on_select
  context.on_preview = opt.on_preview
  context.config = config
  context.selected_idx = 1
  while context.items[context.selected_idx] and (context.items[context.selected_idx].type == 'separator' or context.items[context.selected_idx].type == 'title') do
    context.selected_idx = context.selected_idx + 1
  end

  -- if context.on_preview and context.items[context.selected_idx] then
  --   vim.schedule(function()
  --     context.on_preview(context.items[context.selected_idx], context.selected_idx)
  --   end)
  -- end

  context.buf, context.win = create_popup()

  if api.nvim_get_mode().mode ~= 'i' then
    vim.cmd('startinsert')
  end

  render_menu()

  setup_keymaps()
  setup_autocommands()

  return context.buf, context.win
end

function M.close()
  if context.win and api.nvim_win_is_valid(context.win) then
    api.nvim_win_close(context.win, true)
    context.win = nil
    context.buf = nil
  end

  if context.preview_win and api.nvim_win_is_valid(context.preview_win) then
    api.nvim_win_close(context.preview_win, true)
    context.preview_win = nil
    context.preview_buf = nil
  end

  cleanup_keymaps()

  pcall(api.nvim_del_augroup_by_name, 'PopupMenu')
end

function M.setup(user_config)
  context.config = vim.tbl_deep_extend('force', {}, default_config, user_config or {})

  vim.cmd([[
    hi def link PopupNormal PmenuSbar
    hi def link PopupBorder FloatBorder
    hi def link PopupTitle Title
    hi def link PopupSeparator NonText
  ]])

  return M
end

function M.select(idx)
  if context.buf and api.nvim_buf_is_valid(context.buf) then
    select_item(idx)
  end
end

M.is_opened = function()
  return context.win and api.nvim_win_is_valid(context.win)
end

return M
