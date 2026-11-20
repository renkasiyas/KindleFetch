# KindleFetch

KindleFetch opens in Touch mode from one launcher. Both modes use the same catalog
request, settings, edition order, and verified LibGen download code. The catalog searches LibGen
first and uses the terminal's Anna’s Archive fallback. Results are shared for five minutes so
switching modes keeps the same editions and order. The default library is `/mnt/us/Books`.

## Install and use

Install KUAL and KOReader on your jailbroken Kindle. On an older installation, choose
**Install update** from KindleFetch in KUAL. Reopen KindleFetch once to register the KOReader entry,
then restart KOReader. The checkout's `install.sh` can also install the current release and register
both modes directly.

For a new installation, download `kindlefetch.zip` from
[our releases](https://github.com/renkasiyas/KindleFetch/releases), extract its `kindlefetch` directory
into `extensions/`, and launch it once from KUAL. If the Kindle’s built-in curl cannot connect,
place a compatible curl in `extensions/kindlefetch/bin/curl/`.

- Open **KindleFetch** in KUAL or your Kindle library. If KOReader is already open, choose
  **Search → Kindle Fetch → Open KindleFetch**.
- Choose **Terminal mode** inside KindleFetch and tap **Touch** to return.
- **Updates** are available in Terminal mode and from **Check for updates** in KOReader. Both use the same
  release. The installer verifies the package checksum, keeps settings and existing curl, and
  saves previous app files in `extensions/kindlefetch-rk-hardening/`.

The terminal is based on [justrals/KindleFetch](https://github.com/justrals/KindleFetch).
The touchscreen mode uses the [KindleFetch KOReader interface](https://github.com/william-spongberg/KindleFetch.koplugin).

## Development

Run `tests/parity.sh /path/to/KOReader/common/dkjson.lua luajit` to check ordered results from both
interfaces with a primary and fallback response, verify shared download bytes, and test GUI
registration. Use a public-domain sample for a real-device check.

To build a release, run `./create_release.sh v2.0.0 /path/to/output v2.0.0` and attach the resulting
`kindlefetch.zip` to the tag’s GitHub release.
