local json = require("dkjson")
local ok, release = pcall(json.decode, io.read("*a"))
if not ok or type(release) ~= "table" or release.draft ~= false or release.prerelease ~= false then
    os.exit(1)
end
local tag = release.tag_name
if type(tag) ~= "string" or not tag:match("^v%d+%.%d+%.%d+$") or type(release.assets) ~= "table" then
    os.exit(1)
end
for _, asset in ipairs(release.assets) do
    if type(asset) == "table" and asset.name == "kindlefetch.zip" and type(asset.digest) == "string" then
        local digest = asset.digest:match("^sha256:(%x+)$")
        if digest and #digest == 64 then
            print(tag, digest:lower())
            return
        end
    end
end
os.exit(1)
