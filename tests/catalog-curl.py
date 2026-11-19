#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, os, sys
args = sys.argv[1:]
target = args[args.index("-o") + 1] if "-o" in args else None
url = next(x for x in args if x.startswith("https://"))
mode = os.environ.get("KF_FIXTURE", "primary")
book_data = Path(os.environ["KINDLEFETCH_BASE_DIR"]) / "fixture.epub"
md5 = hashlib.md5(book_data.read_bytes()).hexdigest()
if "config.v3.json" in url:
    answer = '{"latest_version":"3.4.0","mirrors":[{"src":"https://libgen.li/"}]}'
elif "/api/search/" in url:
    if mode == "primary" and "libgen.pw" in url:
        sys.exit(7)
    rows = [{
        "id": edition,"title":title,"author":["Jane Austen"],"language":language,"year":1813,"fileExtension":ext
    } for edition, title, language, ext in (
        (50,'An {edition} "with quotes"','English','epub'), (72,'Edición','Spanish','pdf'),
        (50,'An {edition} "with quotes"','English','epub'), (93,'Unsupported','English','exe'))]
    answer = json.dumps({"isError":False,"result":{"books":rows if mode=="primary" else []}})
elif "/search" in url:
    fmt = '<div class="flex pt-3 pb-3 border-b last:border-b-0 border-gray-100"><a href="/md5/{md5}"><div class="font-bold text-violet-900 line-clamp-[5]" data-content="{title}"><div class="text-gray-800">English · epub · test</div><div class="text-gray-800 font-semibold text-sm leading-[1.2] mt-2">lgli</div>'
    answer = '<a href="?page=2">' + ''.join(fmt.format(md5=h,title=t) for h,t in [(md5,"Anna first"),("1" * 32,"Anna second")])
elif "/api/download/links-by-id" in url:
    answer = json.dumps({"isError":False,"result":{"links":["https://annas-archive.gl/md5/"+md5]}})
elif "/ads.php" in url:
    answer = '<a href="/get.php?key=fixture&amp;book=50">GET</a>'
elif "/get.php" in url:
    answer = book_data.read_bytes()
else:
    sys.exit(7)
if isinstance(answer, str):
    answer = answer.encode()
if target:
    Path(target).write_bytes(answer)
else:
    sys.stdout.buffer.write(answer)
