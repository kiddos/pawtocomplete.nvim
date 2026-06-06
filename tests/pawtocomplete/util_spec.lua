local util = require('pawtocomplete.util')

describe('util', function()
  describe('floating_dimensions', function()
    it('calculates dimensions correctly for regular lines', function()
      local lines = { 'hello', 'world', 'this is a test' }
      local max_height = 10
      local max_width = 20
      local h, w = util.floating_dimensions(lines, max_height, max_width)
      assert.are.equal(3, h)
      assert.are.equal(14, w) -- 'this is a test' is 14 chars
    end)

    it('respects max_height', function()
      local lines = { '1', '2', '3', '4', '5' }
      local max_height = 3
      local max_width = 10
      local h, w = util.floating_dimensions(lines, max_height, max_width)
      assert.are.equal(3, h)
      assert.are.equal(1, w)
    end)

    it('respects max_width', function()
      local lines = { 'this is a very long line' }
      local max_height = 10
      local max_width = 10
      local h, w = util.floating_dimensions(lines, max_height, max_width)
      assert.are.equal(1, h)
      assert.are.equal(10, w)
    end)
    
    it('handles empty lines', function()
      local lines = {}
      local h, w = util.floating_dimensions(lines, 10, 10)
      assert.are.equal(0, h)
      assert.are.equal(0, w)
    end)
  end)

  describe('debounce', function()
    it('only calls the function once after multiple calls', function()
      local count = 0
      local debounced = util.debounce(function()
        count = count + 1
      end, 50)

      debounced()
      debounced()
      debounced()

      assert.are.equal(0, count)

      vim.wait(100, function() return count > 0 end)
      assert.are.equal(1, count)
    end)

    it('passes arguments correctly', function()
      local result = nil
      local debounced = util.debounce(function(val)
        result = val
      end, 20)

      debounced('foo')
      vim.wait(50, function() return result ~= nil end)
      assert.are.equal('foo', result)
    end)
  end)

  describe('throttle', function()
    it('only calls the function once within the timeout', function()
      local count = 0
      local throttled = util.throttle(function()
        count = count + 1
      end, 100)

      throttled()
      throttled()
      throttled()

      -- The first call should trigger a timer that executes later
      -- Wait for the first execution
      vim.wait(150, function() return count > 0 end)
      assert.are.equal(1, count)
      
      -- Call again after timeout
      throttled()
      vim.wait(150, function() return count > 1 end)
      assert.are.equal(2, count)
    end)
  end)
end)
