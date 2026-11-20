-- Read a LibGen search, download manifest, or mirror download page.
local json = require('dkjson')
local action, file = arg[1], arg[2]
if not file or (action ~= 'search' and action ~= 'download-hash' and action ~= 'mirror-link' and action ~= 'torrent-links') then
  os.exit(2)
end
local handle = assert(io.open(file, 'rb'))
local raw = handle:read('*a')
handle:close()

if action == 'mirror-link' then
  for href in raw:gmatch('href%s*=%s*"([^"]+)"') do
    local path = href:gsub('^/', ''):gsub('&amp;', '&')
    if path:match('^get%.php%?[%w%%&=_.~+%-]+$') then
      print(path)
      return
    end
  end
  os.exit(3)
end

if action == 'torrent-links' then
  for href in raw:gmatch('href%s*=%s*"([^"]+)"') do
    if href:match('^/torrents/libgen/[%w_.-]+%.torrent$') or
       href:match('^/torrents/fiction/[%w_.-]+%.torrent$') then
      print(href)
    end
  end
  return
end

local ok, payload = pcall(json.decode, raw)
if not ok or type(payload) ~= 'table' or payload.isError ~= false or
   type(payload.result) ~= 'table' then
  io.stderr:write('LibGen returned invalid data\n')
  os.exit(1)
end

if action == 'download-hash' then
  if type(payload.result.links) == 'table' then
    for _, url in ipairs(payload.result.links) do
      local hash = type(url) == 'string' and url:match('^https://annas%-archive%.[a-z]+/md5/(%x+)/?$')
      if hash and #hash == 32 then
        print(hash:lower())
        return
      end
    end
  end
  os.exit(3)
end

if type(payload.result.books) ~= 'table' then
  io.stderr:write('LibGen search returned invalid data\n')
  os.exit(1)
end
local rows = {}
for _, book in ipairs(payload.result.books) do
  local ext = type(book.fileExtension) == 'string' and book.fileExtension:lower() or ''
  local id = tostring(book.id or '')
  local title = book.title
  if id:match('^%d+$') and type(title) == 'string' and title ~= '' and
     (ext == 'epub' or ext == 'azw3' or ext == 'mobi' or ext == 'pdf') then
    local author = ''
    if type(book.author) == 'table' then author = table.concat(book.author, ' ') end
    local lang = type(book.language) == 'string' and book.language or ''
    local year = type(book.year) == 'number' and tostring(book.year) or ''
    local description = 'LibGen lgli · ' .. lang .. ' · ' .. year .. ' · ' .. ext
    rows[#rows + 1] = {
      author = author, format = ext, id = id, md5 = '', title = title, language = lang, year = year,
      url = 'https://libgen.pw/book/' .. id, description = description,
    }
  end
end
if #rows == 0 then os.exit(3) end
io.write('[\n')
for i, row in ipairs(rows) do
  io.write('  ', json.encode(row), i < #rows and ',\n' or '\n')
end
io.write(']\n')
