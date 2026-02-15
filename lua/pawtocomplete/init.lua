local api = vim.api
local M = {}

M.setup = function(opts)
  local config = require('pawtocomplete.config')
  config.merge_option(opts)

  local completion = require('pawtocomplete.completion')
  local signature = require('pawtocomplete.signature')

  completion.setup()
  signature.setup()

  api.nvim_create_user_command('PawWalk', function()
    local conf = require('pawtocomplete.config').get_config()
    require('pawtocomplete.walk').walk(conf.walk)
  end, {})

  api.nvim_create_user_command('PawStop', function()
    require('pawtocomplete.walk').stop()
  end, {})
end

return M
