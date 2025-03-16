local get_script_dir = function()
  return debug.getinfo(1).source:match('@?(.*/)')
end

local script_dir = get_script_dir()
local target_dir = script_dir .. '../../'

package.cpath = package.cpath
  .. ';'
  .. target_dir .. 'build/lib?.so'

return require('paw')
