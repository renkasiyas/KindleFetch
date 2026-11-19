# KindleFetch for KUAL

The KindleFetch terminal app for Pathfinder, based on [justrals/KindleFetch](https://github.com/justrals/KindleFetch).
It searches LibGen first and verifies downloads against the book's catalog checksum.

## Install and update

1. Install KUAL, kterm, and KOReader on your jailbroken Kindle. KindleFetch uses the Lua runtime bundled with KOReader.
2. Download `kindlefetch.zip` from [our releases](https://github.com/renkasiyas/KindleFetch/releases).
3. For a new installation, extract the `kindlefetch` directory into `extensions/` on your Kindle. If you already
   have KindleFetch, run this checkout's `install.sh` from the Kindle to migrate your installation and settings.
4. Open **KindleFetch** in KUAL. When a newer version is available, choose **Install update** and confirm.

The installer checks the GitHub release checksum before replacing the app and keeps the previous installation in
`extensions/kindlefetch-rk-hardening/`. It carries forward the configuration, Z-Library cookies, and any existing
bundled curl. You can place a compatible curl executable in `extensions/kindlefetch/bin/curl/` if the Kindle's system
curl has trouble connecting.

To build a tagged release, run `./create_release.sh v1.4.0 /path/to/output v1.4.0` and attach the resulting
`kindlefetch.zip` to the corresponding GitHub release.
