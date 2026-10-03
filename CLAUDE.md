# CLAUDE.md

curl for OpenVMS (IA64, x86-64), built with curl's own `projects/vms/build_vms.com`, wrapped
by the same tooling as `~/projects/vms-grep`, `vms-pcre2`, `vms-sed`, `vms-awk` and
`vms-zlib` (read vms-grep's `CLAUDE.md` for the ground rules and VMS/ssh pitfalls; they all
apply). In short:

- **Never edit `staging/`, `cache/` or `out/`.** Upstream files change only through
  `patches/` (listed in `patches/series`); our files live in `overlay/vmsport/`.
- **Use `tools/vms.sh`** for remote work; never raw `ssh host cmd`, never `WAIT` over ssh.
- **Committed files must not contain real node details** (they live in `tools/nodes.conf`),
  **nor credentials**: the user's batch test URL carries a token; it lives only in
  git-ignored `cache/*.com`.
- **Dependencies on each node:** VSI's SSL3 kit (OpenSSL 3.0, `SSL3$INCLUDE`, shared images
  `SSL3$LIBSSL_SHR32`/`SSL3$LIBCRYPTO_SHR32`), and a vms-zlib install tree at
  `<workdir>.ZLIB-1_3_2.INSTALL_<arch>]`, which build.sh defines as `ZLIB$ROOT`.
- **`build_vms.com` generates `config_vms.h`/`curl_config.h` only when the object
  directory has no `curl_config.h`.** After changing a config patch or the default CA
  bundle, run `tools/build.sh <node> CLEAN` first.
- **Names:** VSI's CURL kit owns `SYS$COMMON:[CURL]`, `CURL$ROOT` and `CURL$STARTUP.COM`.
  Ours is product `VMSCURL`: `[VMSCURL]`, `VMSCURL$ROOT`, `VMSCURL$STARTUP.COM`. The
  default CA bundle is compiled in as `VMSCURL$ROOT:[SSL]CACERT.PEM` (patch 0010 plus
  `CURL_CA_BUNDLE_DEFAULT` in `build.com`); the bundle is pinned by URL and SHA-256 in
  `upstream.conf` and fetched by `fetch.sh`.
- **Batch jobs use the TRADITIONAL parse style**, so unquoted upper-case options are
  lowercased (`-F` becomes `-f`). Quote them in test procedures. Patch 0009 prints a note
  when this makes curl fail; it explained the "VSI curl fails silently in batch" report.
- **Exit status:** upstream's `VMS_STS()` typo made every failure severity 3
  (informational); patch 0011 fixes it. Smoke tests check `$SEVERITY`: save it straight
  after the command, because any DCL assignment resets it.
- **Upstream's CLEAN deletes `[...]*curl*.pcsi$desc`/`$text`**, so our PCSI description
  files are named `PRODUCT-<base>.PCSI$DESC`. build.sh fails on undefined symbols and DCL
  errors, which upstream's build_vms.com carries on past (it still produces a CURL.EXE that
  crashes with CALLUNDEFSYM).
- **Compiler quirks:** x86 VSI C 7.7 ACCVIOs on `lib/formdata.c` with `/DEBUG`
  (`/DEBUG=TRACEBACK` is used); x86 ignores `/NESTED_INCLUDE=PRIMARY_FILE`, and `./` on the
  include list makes `lib/curlx/wait.h` hide `<wait.h>` (patch 0005).
- **Versions:** three-part, so curl 8.22.0 with patch level 1 is PCSI `V8.22-0E1`. Bump
  `VMS_PATCH_LEVEL` for any change to a published kit.

```sh
tools/prepare.sh
tools/build.sh <ia64|x86> [ALL|CLEAN]
tools/test.sh <node>            # smoke test (needs network access to example.com)
tools/kit.sh <node>             # PCSI kit -> out/kits/
tools/installcheck.sh <node>    # install, verify, remove (changes the system; ask first)
```

Don't push without the user asking; the remote is `origin` (github.com/issinoho/vms-curl),
branch `main`.
