local JSON = require("json")
local Backend = require("util.sharedbackend")
local StringUtil = require("util.stringutil")
local _ = require("gettext")

local Catalog = {
    NAME = "KindleFetch",
    SOURCE = "libgen",
    startDownload = Backend.startDownload,
}

function Catalog:isCached()
    return false
end

function Catalog:search(query, page)
    local response, err = Backend.run("search", query, page)
    if not response then
        return nil, err
    end
    local ok, result = pcall(JSON.decode, response)
    if not ok or type(result) ~= "table" then
        return nil, _("KindleFetch returned an unreadable catalog response")
    end
    if type(result.books) ~= "table" then
        return nil, type(result.error) == "string" and result.error or _("Catalog request failed")
    end

    local books = {}
    for index, row in ipairs(result.books) do
        books[index] = {
            id = table.concat({ row.id or row.md5 or "", page, index }, ":"),
            source = self.SOURCE,
            catalog_id = row.id,
            checksum = row.md5,
            display_title = row.title,
            title = StringUtil.cleanFileName(row.title),
            authors = row.author,
            file_type = row.format:lower(),
            language = row.language,
            year = row.year,
        }
    end
    return books, nil, result.next_page, #books
end

return Catalog
