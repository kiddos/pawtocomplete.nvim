local M = {}

local config = {
  completion = {
    abbr_max_len = 60,
    menu_max_len = 20,
    delay = 200,
    max_cost = 0.9,
    dist_difference = 0,
    insert_cost = 1,
    delete_cost = 1,
    substitude_cost = 2,
  },
  signature = {
    max_width = 120,
    max_height = 6,
    delay = 100,
  },
  walk = {
    speed = 100,
    step = 1,
  },
}

M.merge_option = function(opt)
  config = vim.tbl_extend('force', config, opt)
end

M.get_config = function()
  return config
end

return M
