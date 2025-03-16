local M = {}

M.setup = function(opts)
  local config = require('pawtocomplete.config')
  config.merge_option(opts)

  local completion = require('pawtocomplete.completion')
  local signature = require('pawtocomplete.signature')

  completion.setup()
  signature.setup()
end

return M
