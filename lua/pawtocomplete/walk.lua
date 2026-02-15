local api = vim.api
local uv = vim.uv or vim.loop

local M = {
  timer = nil,
  win = nil,
  buf = nil
}

local frames = {
[[
  |\__/,|   (`\
|_ _  |.--.) )
( T   )     /
(((^_((_(((_/
]],
[[
  |\__/,|   (`\
|_ _  |.--.) )
( T   )     /
 ((_((_((_((_/
]]
}

function M.stop()
  if M.timer then
    M.timer:stop()
    M.timer:close()
    M.timer = nil
  end
  if M.win and api.nvim_win_is_valid(M.win) then
    api.nvim_win_close(M.win, true)
    M.win = nil
  end
end

function M.walk(opts)
  M.stop()

  opts = opts or {}
  local speed = opts.speed or 100
  local step = opts.step or 1

  M.buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value('bufhidden', 'wipe', { buf = M.buf })

  local width = 18
  local height = 4

  local row = api.nvim_get_option('lines') - height - 3
  local col = 0

  M.win = api.nvim_open_win(M.buf, false, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = 'none',
    zindex = 100,
  })

  api.nvim_set_option_value('winhl', 'Normal:NormalFloat', { win = M.win })

  local frame_idx = 1
  local current_col = col

  M.timer = uv.new_timer()
  M.timer:start(0, speed, vim.schedule_wrap(function()
    if not M.win or not api.nvim_win_is_valid(M.win) then
      M.stop()
      return
    end

    local lines = vim.split(frames[frame_idx], '\n')
    -- Remove trailing empty line if any
    if lines[#lines] == "" then table.remove(lines) end

    api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)

    frame_idx = (frame_idx % #frames) + 1
    current_col = current_col + step

    local max_cols = api.nvim_get_option('columns')
    local current_row = api.nvim_get_option('lines') - height - 3
    if current_col > max_cols then
      current_col = -width
    end

    api.nvim_win_set_config(M.win, {
      relative = 'editor',
      row = current_row,
      col = current_col,
      width = width,
      height = height
    })
  end))
end

return M
