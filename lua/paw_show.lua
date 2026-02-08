local uv = vim.uv

local M = {
  running = false
}

local function run_async(executable, args)
  if M.running then
    return
  end

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  local options = {
    args = args,
    stdio = { nil, stdout, stderr }
  }
  local on_exit = function(code, signal)
    M.running = false
  end
  M.running = true
  uv.spawn(executable, options, on_exit)
end

M.random_show = function()
  -- if math.random(1, 100) > 20 then
  --   return
  -- end

  local script_dir = debug.getinfo(1).source:match('@?(.*/)')
  local target_dir = script_dir .. '../'
  local executable = target_dir .. 'build/paw_show_webp'
  local images = {'paw1.webp', 'paw2.webp'}
  local random_index = math.random(1, #images)
  local selected_image = images[random_index]
  local args = {'--webp', target_dir .. 'images/' .. selected_image }
  run_async(executable, args)
end

return M
