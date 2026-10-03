#!/usr/bin/env bash
# prepare.sh - build a VMS-ready curl source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#
# curl ships its own OpenVMS port (projects/vms: build_vms.com, config_h.com,
# generate_config_vms_h_curl.com), maintained upstream, so there is no
# host-side configure.  Our own VMS files live in vmsport/.
#
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

step "extracting $name"
rm -rf "$stage"; mkdir -p "$top/staging"
tar -xJf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

# overlay/ may only add files; changes to upstream files belong in patches/.
(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

printf 'VERSION=%s\nKIT_VERSION=%s-vms%s\n' "$UPSTREAM_VERSION" "$UPSTREAM_VERSION" \
    "$VMS_PATCH_LEVEL" > "$stage/vmsport/version.env"

# --- PCSI kit inputs (vmsport/kit/MAKE_KIT.COM builds the kit on each node) --
step "PCSI kit inputs"
kit=$stage/vmsport/kit
: "${KIT_PRODUCER:=ISSINOHO}"
# curl versions have three parts (8.22.0): the third is the PCSI update and
# our VMS patch level the ECO, as in vms-awk, so 8.22.0-vms1 is V8.22-0E1.
IFS=. read -r major minor update _ <<< "$UPSTREAM_VERSION"
pcsiversion="V$major.$minor-${update:-0}E$VMS_PATCH_LEVEL"
kitversion="$UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL"
cabundle=$top/cache/$(basename "$CA_BUNDLE_URL")
cadate=$(basename "$CA_BUNDLE_URL" .pem | sed 's/^cacert-//')
subst() {
    sed -e "s/@PRODUCER@/$KIT_PRODUCER/g" -e "s/@BASE@/$1/g" \
        -e "s/@PCSIVERSION@/$pcsiversion/g" -e "s/@VERSION@/$UPSTREAM_VERSION/g" \
        -e "s/@KITVERSION@/$kitversion/g" -e "s/@ARCH@/$2/g" -e "s/@CABUNDLEDATE@/$cadate/g"
}
lc=$(echo "$KIT_PRODUCT" | tr A-Z a-z)
# Named PRODUCT-<base>: upstream's build_vms.com CLEAN deletes [...]*curl*.pcsi$desc.
for base in I64VMS X86VMS; do
    subst $base "" < "$kit/$lc.pcsi\$desc_template" > "$kit/PRODUCT-$base.PCSI\$DESC"
    subst $base "" < "$kit/$lc.pcsi\$text_template" > "$kit/PRODUCT-$base.PCSI\$TEXT"
done
rm -f "$kit/$lc.pcsi\$desc_template" "$kit/$lc.pcsi\$text_template"
mv "$kit/$lc\$startup.com" "$kit/$KIT_PRODUCT\$STARTUP.COM"
subst "" "IA64 and x86-64" < "$kit/readme.vms" > "$kit/README.VMS"; rm -f "$kit/readme.vms"
cp "$cabundle" "$kit/CACERT.PEM"
mkdir -p "$kit/doc"
cp "$stage/COPYING" "$kit/doc/COPYING."
cp "$stage/docs/MANUAL.md" "$kit/doc/MANUAL.TXT"
cp "$stage/docs/SSLCERTS.md" "$kit/doc/SSLCERTS.TXT"
cp "$stage/RELEASE-NOTES" "$kit/doc/RELEASE-NOTES."
printf 'KIT_PRODUCER=%s\nKIT_PRODUCT=%s\nPCSI_VERSION=%s\nKIT_VERSION=%s\n' "$KIT_PRODUCER" \
    "$KIT_PRODUCT" "$pcsiversion" "$kitversion" > "$kit/kit.env"
step "staged $stage"
