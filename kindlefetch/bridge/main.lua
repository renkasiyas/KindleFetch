local root = (os.getenv("KINDLEFETCH_BASE_DIR") or "/mnt/us") .. "/extensions/kindlefetch/gui"
local previous_path = package.path
package.path = root .. "/?.lua;" .. previous_path
local loaded, plugin = pcall(dofile, root .. "/main.lua")
package.path = previous_path
if not loaded then
    error(plugin)
end
return plugin
