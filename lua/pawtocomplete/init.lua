local M = {}

M.setup = function(opts)
  local config = require('pawtocomplete.config')
  config.merge_option(opts)

  local completion = require('pawtocomplete.completion')
  local signature = require('pawtocomplete.signature')
  local sparky = require('pawtocomplete.sparky')

  completion.setup()
  signature.setup()
  sparky.setup()
end

return M
