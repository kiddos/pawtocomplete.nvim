local paw = require('pawtocomplete.paw')

local function generate_random_string(length)
  local characters = " abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local result = ""

  for i = 1, length do
      local random_index = math.random(1, #characters)
      result = result .. characters:sub(random_index, random_index)
  end
  return result
end

local function str_trim(s)
  return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

local function trim_long_text(text, width)
  text = str_trim(text)
  if #text > width then
    return string.sub(text, 1, width + 1) .. '...'
  end
  return text
end

local function is_whitespace(s)
  if type(s) == 'string' then return s:find('^%s*$') end
  if type(s) == 'table' then
    for _, val in pairs(s) do
      if not is_whitespace(val) then return false end
    end
    return true
  end
  return false
end

local function table_get(t, id)
  if type(id) ~= 'table' then return table_get(t, { id }) end
  local success, res = true, t
  for _, i in ipairs(id) do
    success, res = pcall(function() return res[i] end)
    if not success or res == nil then return end
  end
  return res
end


describe('paw', function()
  it('functions', function()
    print(vim.inspect(paw))
  end)

  it('trim_long_text', function()
    assert(paw.trim_long_text('text', 20) == 'text')
    assert(paw.trim_long_text('the quick brown fox jumps over the lazy dog', 20) == 'the quick brown fox ...')
  end)

  it('benchmark trim_long_text', function()
    local start = os.clock()
    local result = {}
    for i = 1,10000 do
      local text = generate_random_string(100)
      table.insert(result, paw.trim_long_text(text, 20))
    end
    local fin = os.clock() - start
    print('cpp implementation:', fin)

    start = os.clock()
    result = {}
    for i = 1,10000 do
      local text = generate_random_string(100)
      table.insert(result, trim_long_text(text, 20))
    end
    fin = os.clock() - start
    print('lua implementation:', fin)
  end)

  it('table_get', function()
    local data = {
      key1 = {
        key2 = {
          str_data = 'text',
          int_data = 123,
          key3 = {
            bool_data = false,
          }
        }
      }
    }
    assert(paw.table_get(data, { 'key1', 'key2', 'str_data' }) == 'text')
    assert(paw.table_get(data, { 'key1', 'key2', 'str_data' }) == 'text')
    assert(paw.table_get(data, { 'key1', 'key2', 'int_data' }) == 123)
    assert(paw.table_get(data, { 'key1', 'key2', 'key3', 'bool_data' }) == false)
    assert(type(paw.table_get(data, { 'key1', 'key2', 'key3' })) == 'table')
  end)

  it('benchmark table_get', function()
    local data = {
      key1 = {
        key2 = {
          str_data = 'text',
          int_data = 123,
          key3 = {
            bool_data = false,
          }
        }
      }
    }

    local start = os.clock()
    for i = 1,100000 do
      paw.table_get(data, { 'key1', 'key2', 'str_data' })
    end
    local fin = os.clock() - start
    print('cpp implementation:', fin)

    start = os.clock()
    for i = 1,100000 do
      table_get(data, { 'key1', 'key2', 'str_data' })
    end
    fin = os.clock() - start
    print('lua implementation:', fin)
  end)

  it('benchmark is_whitespace', function()
    local data = ''
    local start = os.clock()
    for i = 1,100000 do
      paw.is_whitespace(data)
    end
    local fin = os.clock() - start
    print('cpp implementation:', fin)

    start = os.clock()
    for i = 1,100000 do
      is_whitespace(data)
    end
    fin = os.clock() - start
    print('lua implementation:', fin)
  end)

  it('benchmark is_whitespace multiple spaces', function()
    local data = { '', '', '' }
    local start = os.clock()
    for i = 1,100000 do
      paw.is_whitespace(data)
    end
    local fin = os.clock() - start
    print('cpp implementation:', fin)

    start = os.clock()
    for i = 1,100000 do
      is_whitespace(data)
    end
    fin = os.clock() - start
    print('lua implementation:', fin)
  end)

  it('filter_and_sort', function()
    local completion_items = {
      {
        label = 'text',
        kind = 1,
        detail = 'detail1',
      },
      {
        label = 'foo',
        kind = 2,
        detail = 'detail2',
        textEdit = {
          range = {
            start = {
              line = 1,
              character = 2,
            },
            ["end"] = {
              line = 3,
              character = 10,
            },
          },
        },
      },
      {
        label = 'bar',
        kind = 3,
        detail = 'detail3',
      },
    }

    local option = {
      keyword = 'f',
      insert_cost = 1,
      delete_cost = 1,
      substitude_cost = 2,
      max_cost = 2.5,
    }
    local param = {
      line = 1,
      start = 2,
      cursor = 10,
    }
    local output = paw.filter_and_sort(completion_items, option, param)
    assert(#output == 1)

    local item = output[1]
    assert(item.label == 'foo')
    assert(item.cost == 0)
    assert(item.kind == 2)
    assert(item.detail == 'detail2')
    assert(item.textEdit ~= nil)
    assert(item.textEdit.range.start.line == 1)
    assert(item.textEdit.range.start.character == 2)
    assert(item.textEdit.range['end'].line == 3)
    assert(item.textEdit.range['end'].character == 10)
  end)

  it('find_last_word_index', function()
    assert(paw.find_last_word_index('hello world') == 6)
    assert(paw.find_last_word_index('hello world ') == nil)
    assert(paw.find_last_word_index(' helloworld') == 1)
    assert(paw.find_last_word_index('helloworld') == 0)
  end)

  it('find_last_trigger_index', function()
    assert(paw.find_last_trigger_index('hello.world', '.') == 5)
    assert(paw.find_last_trigger_index('hello.world.', '.') == 11)
    assert(paw.find_last_trigger_index('hello world', '.') == nil)
    assert(paw.find_last_trigger_index('hello.', '.') == 5)
  end)

  it('find_trigger_context', function()
    local context = paw.find_trigger_context({ '.' }, 'hello.', 5)
    assert(context.triggerCharacter == '.')
    assert(context.triggerKind == 2)

    context = paw.find_trigger_context({ '.' }, 'hello.world', 5 + 1)
    assert(context == nil)
  end)

  it('cat', function()
    -- The cat emoji is one of these: 🐱, 😺, 😸, 😽, 😼, 😾, 😿
    local emoji = paw.cat_emoji()
    assert(emoji ~= nil)

    paw.interact()
    local emoji2 = paw.cat_emoji()
    assert(emoji2 ~= nil)
  end)

  it('cache', function()
    local key = {
      bufnr = 1,
      line = 1,
      col = 1,
      word = 'word',
    }
    local value = {
      {
        label = 'text',
        kind = 1,
        detail = 'detail1',
      },
    }
    paw.put_cache_result(key, value)
    assert(paw.has_cache_value(key) == true)

    local result = paw.get_cache_result(key)
    assert(#result == 1)
    assert(result[1].label == 'text')

    paw.remove_cache_result(key)
    assert(paw.has_cache_value(key) == false)
  end)
end)
