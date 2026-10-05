#!/usr/bin/env bash
# build.sh <node> [target] [KEEP_GOING] - push the prepared tree and run [.VMS]BUILD.COM on <node>.
# The build runs in an ssh session (batch queues may be busy); its log is printed and saved to out/build-<node>.log.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: build.sh <node> [target]}
target=${2:-ALL}
keep=${3:-}
. "$top/upstream.conf"
remote=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _ | tr a-z A-Z)
read -r _ _ _ _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")

"$top/tools/push.sh" "$node"
mkdir -p "$top/out"
job=$top/cache/build-$node.com
cat > "$job" <<DCL
\$ set noon
\$ set process/parse_style=extended
\$! ZLIB\$ROOT: the node's vms-zlib install tree (ZLIB_TREE in upstream.conf)
\$ zarch = f\$edit(f\$getsyi("ARCH_NAME"), "UPCASE")
\$ zdir = "${WORKDIR%]}.$ZLIB_TREE.INSTALL_" + zarch + "]"
\$ zdev = f\$parse(zdir,,,"DEVICE","NO_CONCEAL")
\$ zroot = f\$parse(zdir,,,"DIRECTORY","NO_CONCEAL") - "][" - "]" + ".]"
\$ define/process/translation_attributes=concealed ZLIB\$ROOT 'zdev''zroot'
\$! ZSTD\$ROOT: the node's vms-zstd install tree (ZSTD_TREE in upstream.conf)
\$ zdir = "${WORKDIR%]}.$ZSTD_TREE.INSTALL_" + zarch + "]"
\$ zdev = f\$parse(zdir,,,"DEVICE","NO_CONCEAL")
\$ zroot = f\$parse(zdir,,,"DIRECTORY","NO_CONCEAL") - "][" - "]" + ".]"
\$ define/process/translation_attributes=concealed ZSTD\$ROOT 'zdev''zroot'
\$ purge/nolog ${WORKDIR%]}.$remote...]*.*
\$ @${WORKDIR%]}.$remote.VMSPORT]BUILD.COM $target $keep
DCL
VMS_TIMEOUT=${VMS_BUILD_TIMEOUT:-5400} "$top/tools/vms.sh" "$node" run "$job" | tee "$top/out/build-$node.log"
grep -q 'BUILD: done' "$top/out/build-$node.log"
# Upstream's build_vms.com carries on past failed compiles and links with
# undefined symbols, and still produces CURL.EXE, which then crashes at run time
# (%SYSTEM-F-CALLUNDEFSYM).  Treat both as build failures.
if grep -aE 'USEUNDEF|UNDFSYM|%DCL-[WEF]-|%CC-[EF]-|%LIBRAR-[EF]-|%LIBRAR-W-OPENIN' "$top/out/build-$node.log" >&2; then
    echo "build: errors or undefined symbols in out/build-$node.log" >&2
    exit 1
fi
