local script_dir = debug.getinfo(1).source:match('@?(.*/)')
local target_dir = script_dir .. '../../'

package.cpath = package.cpath
  .. ';'
  .. target_dir .. 'build/lib?.so'

return require('paw')
