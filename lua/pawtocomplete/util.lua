local api = vim.api
local fn = vim.fn

local M = {}

M.floating_dimensions = function(lines, max_height, max_width)
  local height = math.min(#lines, max_height)

  -- maximum width
  local width = 0
  local l_width
  for i, l in ipairs(lines) do
    l_width = fn.strdisplaywidth(l)
    if i <= height and width < l_width then width = l_width end
  end
  width = math.min(width, max_width)
  return height, width
end

M.open_action_window = function(container, opts)
  if container.window then
    M.close_action_window(container)
  end

  local win = api.nvim_open_win(container.buffer, false, opts)
  api.nvim_set_option_value('linebreak', true, { win = win })
  api.nvim_set_option_value('breakindent', false, { win = win })
  container.window = win
end

M.close_action_window = function(container)
  if container.window then
    api.nvim_win_close(container.window, true)
  end
  container.window = nil
end

M.debounce = function(callback, timeout)
  local timer = nil
  local f = function(...)
    local t = { ... }
    local handler = function()
      callback(unpack(t))
    end

    if timer ~= nil then
      timer:stop()
    end
    timer = vim.defer_fn(handler, timeout)
  end
  return f
end

M.throttle = function(callback, timeout)
  local timer = nil
  local f = function(...)
    local t = { ... }
    if timer ~= nil then
      return
    end

    timer = vim.defer_fn(function()
      callback(unpack(t))
      timer = nil
    end, timeout)
  end
  return f
end

return M
