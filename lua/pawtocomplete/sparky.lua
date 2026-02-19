local util = require('pawtocomplete.util')

local M = {}

local pipe_path = "/tmp/sparky_rpc"

M.start = function()
  local script_dir = debug.getinfo(1).source:match('@?(.*/)')
  local target_dir = script_dir .. '../../'
  local executable = target_dir .. 'build/sparky'
  local sprite_folder = target_dir .. 'images/sparky'
  local command = {executable, '--sprite-folder', sprite_folder }
  vim.fn.jobstart(command, {detach = true})
end

M.setup = function()
  M.start()

  vim.api.nvim_create_user_command('SparkyStart', function()
    M.start()
  end, {})

  vim.api.nvim_create_user_command('SparkyStop', function()
    M.close()
  end, {})
end

local function write_to_pipe(json_payload)
  local file = io.open(pipe_path, "w")
  if file then
    file:write(json_payload .. "\n")
    file:flush()
    file:close()
  else
  end
end

M.set_emotion = function(emotion)
  local rpc = {
    jsonrpc = "2.0",
    method = "emotion",
    params = emotion,
  }
  local json_payload = vim.json.encode(rpc)
  write_to_pipe(json_payload)
end

M.close = function()
  local rpc = {
    jsonrpc = "2.0",
    method = "close",
  }
  local json_payload = vim.json.encode(rpc)
  write_to_pipe(json_payload)
end

M.update_emotion = util.debounce(function()
  local emotions = {'idle1', 'idle2', 'idle3', 'happy1', 'tired'}
  local index = math.random(1, #emotions)
  M.set_emotion(emotions[index])
end, 1000)

return M
