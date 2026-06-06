local menu = require('pawtocomplete.completion_menu')
local api = vim.api

describe('completion_menu', function()
  before_each(function()
    menu.setup()
  end)

  after_each(function()
    menu.close()
  end)

  it('opens and closes the menu', function()
    local items = {
      { label = 'item1', kind = 1, cost = 0 },
      { label = 'item2', kind = 1, cost = 0 },
    }
    local buf, win = menu.open(items, {})

    assert.is_not_nil(buf)
    assert.is_not_nil(win)
    assert.is_true(api.nvim_win_is_valid(win))
    assert.is_true(menu.is_opened())

    menu.close()
    assert.is_false(menu.is_opened())
  end)

  it('can navigate the menu', function()
    local items = {
      { label = 'item1', kind = 1, cost = 0 },
      { label = 'item2', kind = 1, cost = 0 },
      { label = 'item3', kind = 1, cost = 0 },
    }
    menu.open(items, {})

    local win = nil
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(w).relative ~= "" then
        win = w
        break
      end
    end
    assert.is_not_nil(win)

    local pos = api.nvim_win_get_cursor(win)
    assert.are.equal(1, pos[1])

    menu.select(2)
  end)

  it('handles empty items', function()
    local buf, win = menu.open({}, {})
    assert.is_nil(buf)
    assert.is_nil(win)
    assert.is_false(menu.is_opened())
  end)
end)
