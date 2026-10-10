local completion = require('pawtocomplete.completion')
local api = vim.api

describe('completion text edit and snippet expansion', function()
  local bufnr

  before_each(function()
    bufnr = api.nvim_create_buf(false, true)
    api.nvim_win_set_buf(0, bufnr)
  end)

  after_each(function()
    if api.nvim_buf_is_valid(bufnr) then
      api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('preserves code after the cursor when expanding snippet without prefix in middle of line', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo(, bar)' })
    api.nvim_win_set_cursor(0, { 1, 4 })

    local item = {
      label = 'snippet',
      insertTextFormat = 2,
      textEdit = {
        range = {
          start = { line = 0, character = 4 },
          ['end'] = { line = 0, character = 4 },
        },
        newText = 'snippet($1)',
      },
    }

    completion.apply_text_edit(item)
    assert.are.equal('foo(snippet(), bar)', api.nvim_get_current_line())
  end)

  it('replaces typed prefix and preserves suffix when expanding snippet in middle of line', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo(ba, bar)' })
    api.nvim_win_set_cursor(0, { 1, 6 })

    local item = {
      label = 'baz',
      insertTextFormat = 2,
      textEdit = {
        range = {
          start = { line = 0, character = 4 },
          ['end'] = { line = 0, character = 6 },
        },
        newText = 'baz($1)',
      },
    }

    completion.apply_text_edit(item)
    assert.are.equal('foo(baz(), bar)', api.nvim_get_current_line())
  end)

  it('preserves suffix after cursor when snippet textEdit has no end range', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo(, bar)' })
    api.nvim_win_set_cursor(0, { 1, 4 })

    local item = {
      label = 'snippet',
      insertTextFormat = 2,
      textEdit = {
        range = {
          start = { line = 0, character = 4 },
        },
        newText = 'snippet($1)',
      },
    }

    completion.apply_text_edit(item)
    assert.are.equal('foo(snippet(), bar)', api.nvim_get_current_line())
  end)

  it('expands snippet at end of line without issue', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo(sn' })
    api.nvim_win_set_cursor(0, { 1, 6 })

    local item = {
      label = 'snippet',
      insertTextFormat = 2,
      textEdit = {
        range = {
          start = { line = 0, character = 4 },
          ['end'] = { line = 0, character = 6 },
        },
        newText = 'snippet($1)',
      },
    }

    completion.apply_text_edit(item)
    assert.are.equal('foo(snippet()', api.nvim_get_current_line())
  end)

  it('applies non-snippet text edits and preserves suffix', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'foo(ba, bar)' })
    api.nvim_win_set_cursor(0, { 1, 6 })

    local item = {
      label = 'baz',
      insertTextFormat = 1,
      textEdit = {
        range = {
          start = { line = 0, character = 4 },
          ['end'] = { line = 0, character = 6 },
        },
        newText = 'baz',
      },
    }

    completion.apply_text_edit(item)
    assert.are.equal('foo(baz, bar)', api.nvim_get_current_line())
  end)

  it('ignores text edit if cursor line does not match edit line', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'line 2' })
    api.nvim_win_set_cursor(0, { 2, 0 })

    local item = {
      label = 'snippet',
      insertTextFormat = 2,
      textEdit = {
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 6 },
        },
        newText = 'replaced',
      },
    }

    completion.apply_text_edit(item)
    assert.are.equal('line 2', api.nvim_get_current_line())
  end)
end)
