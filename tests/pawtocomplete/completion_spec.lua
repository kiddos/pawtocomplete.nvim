local completion = require('pawtocomplete.completion')
local paw = require('pawtocomplete.paw')
local popup_menu = require('pawtocomplete.completion_menu')
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

  it('applies additionalTextEdits alongside non-snippet textEdit and updates cursor', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { '', 'local x = fo' })
    api.nvim_win_set_cursor(0, { 2, 12 })

    local item = {
      label = 'foobar',
      insertTextFormat = 1,
      textEdit = {
        range = {
          start = { line = 1, character = 10 },
          ['end'] = { line = 1, character = 12 },
        },
        newText = 'foobar',
      },
      additionalTextEdits = {
        {
          range = {
            start = { line = 0, character = 0 },
            ['end'] = { line = 0, character = 0 },
          },
          newText = "local foobar = require('foobar')\n",
        },
      },
    }

    completion.apply_text_edit(item)
    assert.are.same(
      { "local foobar = require('foobar')", '', 'local x = foobar' },
      api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
    assert.are.same({ 3, 16 }, api.nvim_win_get_cursor(0))
  end)

  it('applies additionalTextEdits alongside snippet textEdit', function()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { '', 'local x = fo' })
    api.nvim_win_set_cursor(0, { 2, 12 })

    local item = {
      label = 'foobar',
      insertTextFormat = 2,
      textEdit = {
        range = {
          start = { line = 1, character = 10 },
          ['end'] = { line = 1, character = 12 },
        },
        newText = 'foobar($1)',
      },
      additionalTextEdits = {
        {
          range = {
            start = { line = 0, character = 0 },
            ['end'] = { line = 0, character = 0 },
          },
          newText = "local foobar = require('foobar')\n",
        },
      },
    }

    completion.apply_text_edit(item)
    assert.are.same(
      { "local foobar = require('foobar')", '', 'local x = foobar()' },
      api.nvim_buf_get_lines(bufnr, 0, -1, false)
    )
  end)

  it('preserves item.data for completionItem/resolve and applies resolved fields', function()
    paw.clear_completion_items()
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'fo' })
    api.nvim_win_set_cursor(0, { 1, 2 })

    local captured_request = nil
    local captured_handler = nil
    local orig_get_client = vim.lsp.get_client_by_id
    local orig_mode = vim.fn.mode
    local orig_open = popup_menu.open
    local orig_refresh = popup_menu.refresh_preview

    local fake_client = {
      id = 99,
      server_capabilities = {
        completionProvider = {
          resolveProvider = true,
        },
      },
      request = function(_, method, params, handler, _)
        captured_request = { method = method, params = params }
        captured_handler = handler
      end,
    }

    vim.lsp.get_client_by_id = function(id)
      if id == 99 then
        return fake_client
      end
      return orig_get_client(id)
    end
    vim.fn.mode = function()
      return 'i'
    end

    local menu_items = nil
    local menu_opts = nil
    local refreshed = false
    popup_menu.open = function(items, opts)
      menu_items = items
      menu_opts = opts
    end
    popup_menu.refresh_preview = function()
      refreshed = true
    end

    local ok, err = pcall(function()
      paw.insert_items({
        {
          label = 'foobar',
          kind = 3,
          data = { id = 123, source = 'mod' },
        },
      }, 99, bufnr, 1, 2)

      completion.show_completion(0)
      assert.is_not_nil(menu_items)
      assert.are.equal(1, #menu_items)
      assert.are.same({ id = 123, source = 'mod' }, menu_items[1].data)

      menu_opts.on_preview(menu_items[1], 1)
      assert.is_not_nil(captured_request)
      assert.are.equal('completionItem/resolve', captured_request.method)
      assert.are.same({ id = 123, source = 'mod' }, captured_request.params.data)
      assert.is_nil(captured_request.params.clientId)
      assert.is_nil(captured_request.params.cost)

      local resolved_edits = {
        {
          range = {
            start = { line = 0, character = 0 },
            ['end'] = { line = 0, character = 0 },
          },
          newText = "local foobar = 1\n",
        },
      }
      captured_handler(nil, {
        label = 'foobar',
        detail = 'fn()',
        documentation = { kind = 'markdown', value = 'Resolved docs' },
        additionalTextEdits = resolved_edits,
      })

      assert.is_true(refreshed)
      assert.are.equal('fn()', menu_items[1].detail)
      assert.are.same({ kind = 'markdown', value = 'Resolved docs' }, menu_items[1].documentation)
      assert.are.same(resolved_edits, menu_items[1].additionalTextEdits)
    end)

    vim.lsp.get_client_by_id = orig_get_client
    vim.fn.mode = orig_mode
    popup_menu.open = orig_open
    popup_menu.refresh_preview = orig_refresh
    paw.clear_completion_items()

    if not ok then
      error(err)
    end
  end)
end)
