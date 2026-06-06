local config = require('pawtocomplete.config')

describe('config', function()
  it('get_config returns default values', function()
    local cfg = config.get_config()
    assert.are.table(cfg)
    assert.are.table(cfg.completion)
    assert.are.equal(60, cfg.completion.abbr_max_len)
    assert.are.equal(20, cfg.completion.menu_max_len)
  end)

  it('merge_option updates the configuration', function()
    config.merge_option({
      completion = {
        abbr_max_len = 100,
      }
    })
    local cfg = config.get_config()
    assert.are.equal(100, cfg.completion.abbr_max_len)
    -- Verify other values are preserved (assuming force merge doesn't wipe them)
    assert.are.equal(20, cfg.completion.menu_max_len)
  end)
end)
