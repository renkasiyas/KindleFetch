local Trapper = require("ui/trapper")
local lfs = require("libs/libkoreader-lfs")
local CurlUtil = require("util.curlutil")
local HttpUtil = require("util.httputil")
local _ = require("gettext")

local Backend = {}
local root = assert(debug.getinfo(1, "S").source:match("^@(.+)/gui/util/sharedbackend%.lua$"))

local function command(...)
    local parts = { "sh", CurlUtil.shellQuote(root .. "/bin/command.sh") }
    for index = 1, select("#", ...) do
        parts[#parts + 1] = CurlUtil.shellQuote(tostring(select(index, ...)))
    end
    return table.concat(parts, " ")
end

function Backend.run(...)
    local cmd = "(" .. command(...) .. "; printf '\\n%d\\n' $?) 2>/dev/null"
    local output
    if Trapper:isWrapped() then
        local done
        done, output = Trapper:dismissablePopen(cmd, HttpUtil.getTrapWidget())
        if not done then
            return nil, HttpUtil.CANCELLED
        end
    else
        local pipe = io.popen(cmd)
        if pipe then
            output = pipe:read("*a")
            pipe:close()
        end
    end
    local body, status = (output or ""):match("^(.*)\n(%d+)\n$")
    if status ~= "0" then
        return nil, _("KindleFetch could not complete the request")
    end
    return (body:gsub("%s+$", ""))
end

local saved_date, library
function Backend.downloadDir()
    local date = lfs.attributes(root .. "/bin/kindlefetch_config", "modification")
    if not library or date ~= saved_date then
        library = Backend.run("download-dir")
        saved_date = date
    end
    return library
end

function Backend.setDownloadDir(path)
    local ok, err = Backend.run("set-download-dir", path)
    if ok then
        library = nil
    end
    return ok, err
end

function Backend.startDownload(book, destination)
    local exit_file = CurlUtil.createExitFile()
    local cmd = command("download", book.catalog_id or "", book.checksum or "", book.file_type, destination)
    local pid, err = CurlUtil.spawnCurlPid(CurlUtil.echoPid(CurlUtil.saveExitCode(cmd, exit_file)))
    if not pid then
        return nil, err
    end
    return pid, exit_file
end

return Backend
