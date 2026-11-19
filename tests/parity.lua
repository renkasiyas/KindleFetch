local base = assert(os.getenv("KINDLEFETCH_BASE_DIR"))
package.path = base .. "/extensions/kindlefetch/gui/?.lua;" .. base .. "/koreader/common/?.lua;" .. package.path
local json = require("dkjson")
package.loaded.json = json
package.loaded.gettext = function(s)
    return s
end
package.loaded["libs/libkoreader-lfs"] = {
    attributes = function()
        return 0
    end,
}
package.loaded["ui/trapper"] = {
    isWrapped = function()
        return false
    end,
}
package.loaded["util.httputil"] = {}
package.loaded["util.stringutil"] = {
    cleanFileName = function(s)
        return s
    end,
}
local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end
package.loaded["util.curlutil"] = {
    shellQuote = quote,
    createExitFile = function()
        return base .. "/exit-code"
    end,
    saveExitCode = function(cmd, path)
        return "(" .. cmd .. "; echo $? > " .. quote(path) .. ") >/dev/null 2>&1"
    end,
    echoPid = function(cmd)
        return cmd
    end,
    spawnCurlPid = function(cmd)
        os.execute(cmd)
        return 1
    end,
}
local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end
local expected = json.decode(read(base .. "/terminal-result.json"))
local display = read(base .. "/terminal-display.txt")
local source = require("api.sharedcatalog")
local actual, err, page = source:search("Pride & Prejudice?", 1)
assert(actual, err)
assert(#expected.books == #actual and #actual > 0)
assert(page == expected.next_page)
for index, row in ipairs(expected.books) do
    assert(actual[index].display_title == row.title)
    assert(actual[index].catalog_id == row.id)
    assert(actual[index].checksum == row.md5)
    assert(actual[index].authors == row.author)
    assert(actual[index].file_type == row.format:lower())
    assert(display:find(row.title, 1, true))
end
if os.getenv("KF_FIXTURE") == "primary" then
    assert(#actual == 3 and actual[1].catalog_id == "50" and actual[2].catalog_id == "72")
    local terminal = base .. "/Books/An__edition___with_quotes_.epub"
    local list = assert(io.popen("find " .. quote(base .. "/Books") .. " -type f"))
    terminal = assert(list:read("*l"))
    list:close()
    source.startDownload(actual[1], base .. "/gui.epub.part")
    assert(read(base .. "/exit-code"):match("^0"))
    assert(read(base .. "/gui.epub.part") == read(terminal))
    print("Primary results, duplicate editions, order, titles, multiple languages, and shared download verified.")
else
    assert(#actual == 2 and expected.source:match("^Anna"))
    assert(actual[1].display_title == "Anna first" and actual[2].display_title == "Anna second")
    assert(actual[1].checksum:match("^%x+$") and #actual[1].checksum == 32)
    assert(page == 2)
    print("Anna fallback results, source, order, and pagination agree in terminal and GUI.")
end
