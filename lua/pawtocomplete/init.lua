local M = {}

M.setup = function(opts)
  local min_version = "0.12.0"
  local expected_version = vim.version.parse(min_version)
  if expected_version then
    if vim.version.cmp(vim.version(), expected_version) < 0 then
      vim.notify(
        string.format("[my-plugin] requires Neovim >= %s", min_version),
        vim.log.levels.ERROR
      )
      return
    end
  end

  local config = require('pawtocomplete.config')
  config.merge_option(opts)

  local completion = require('pawtocomplete.completion')
  local signature = require('pawtocomplete.signature')

  completion.setup()
  signature.setup()
end

return M
