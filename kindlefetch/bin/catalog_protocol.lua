local json = require("dkjson")

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function line(text)
    return tostring(text or ""):gsub("[%c]", " ")
end

local action, path = arg[1], arg[2]

if action == "reply" then
    local status = tonumber(arg[3])
    if status == 0 then
        local books = assert(json.decode(assert(read(path .. "/search_results.json"))))
        local source = (read(path .. "/last_search_source") or ""):match("^(.-)\n?$")
        local page = tonumber(read(path .. "/last_search_page"))
        local last_page = tonumber(read(path .. "/last_search_last_page"))
        print(json.encode({
            books = books,
            source = source,
            next_page = source:match("^Anna") and page and last_page and page < last_page and page + 1 or nil,
        }))
    elseif status == 3 then
        print('{"books":[]}')
    else
        local diagnostic = read(path .. "/last_search_diagnostic") or "Catalog request failed"
        print(json.encode({ error = diagnostic:gsub("%s+$", "") }))
    end
    return
end

if action == "anna" then
    local html = assert(read(path))
    local marker = '<div class="flex pt-3 pb-3 border-b last:border-b-0 border-gray-100">'
    local entities = { amp = "&", quot = '"', apos = "'", lt = "<", gt = ">", ["#39"] = "'", nbsp = " " }
    local function decoded(value)
        return ((value or ""):gsub("&([#%w]+);", function(entity) return entities[entity] end))
    end
    local function trim(value)
        return (value:gsub("^%s+", ""):gsub("%s+$", ""))
    end
    local books = setmetatable({}, { __jsontype = "array" })
    local first = html:find(marker, 1, true)
    while first do
        local start = first + #marker
        first = html:find(marker, start, true)
        local segment = html:sub(start, first and first - 1 or #html)
        local title = segment:match('class="font%-bold text%-violet%-900 line%-clamp%-%[5%]"%s+data%-content="([^"]+)"')
        if title then
            local hash = segment:match('href="/md5/(%x+)"')
            if not hash or #hash ~= 32 then
                hash = ""
            end
            local author = segment:match('class="[^"]*font%-bold[^"]*text%-amber%-900[^"]*line%-clamp%-%[2%][^"]*"%s+data%-content="([^"]+)"')
            local info = segment:match('<div class="text%-gray%-800[^"]*"[^>]*>([^<]+)') or ""
            local language, format = info:match("^(.-) · (.-) · ")
            if not format then
                language, format = info:match("^(.-) · (%w+)")
            end
            local desc = segment:match('class="[^"]*text%-gray%-800[^"]*font%-semibold[^"]*text%-sm[^"]*leading%-%[1%.2%][^"]*mt%-2[^"]*"[^>]*>(.-)</div>') or ""
            desc = decoded(desc:gsub("<script[^>]*>.-</script>", ""):gsub("<[^>]+>", ""))
            books[#books + 1] = {
                author = trim(decoded(author)), format = trim(format or ""), language = trim(language or ""),
                md5 = hash:lower(), title = trim(decoded(title)), url = arg[3] .. "/md5/" .. hash,
                description = trim(desc),
            }
        end
    end
    print(json.encode(books))
    return
end

local books = assert(json.decode(assert(read(path))))
if action == "count" then
    print(#books)
elseif action == "field" then
    local book = books[tonumber(arg[3])]
    if book then
        print((line(book[arg[4]])))
    end
elseif action == "render" then
    local first = assert(tonumber(arg[3]))
    local last = math.min(first + assert(tonumber(arg[4])), #books)
    for index = first + 1, last do
        local book = books[index]
        local title = line(book.title)
        if arg[5] == "true" then
            print(string.format("%2d. %s by %s in %s format\n", index - first, title, line(book.author), line(book.format)))
        else
            print(string.format("%2d. %s", index - first, title))
            if type(book.description) == "string" and book.description ~= "" and book.description ~= "null" then
                print("    " .. line(book.description))
            end
            print()
        end
    end
else
    os.exit(2)
end
