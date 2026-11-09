#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the LAVA NFS rootfs images (lava-image.<arch>-1.tar.xz) with KIWI NG
# inside an openSUSE Tumbleweed container, so the build host can be any Linux
# with podman or docker. Foreign architectures run under QEMU user emulation:
# the host needs binfmt_misc handlers for them (Debian/Fedora: qemu-user-static
# or qemu-user-binfmt).
#
# The result goes to OUTDIR/<tag>/: the images, SHA256SUMS and BUILDINFO. The
# script then prints the gh command that publishes them as a release of
# igaw/lava-artifacts; it never uploads anything itself.

set -euo pipefail

container_image=registry.opensuse.org/opensuse/tumbleweed:latest
release_repo=igaw/lava-artifacts
desc_rel=suse/suse-tumbleweed/lava-image

usage() {
	cat <<EOF
usage: $(basename "$0") [options] [ARCH...]

ARCH: x86_64 aarch64 armv7l (default: all three)

options:
  -o DIR     output directory (default: ./build); images land in DIR/TAG/
  -t TAG     release tag (default: rootfs-$(date +%Y.%m.%d))
  -e ENGINE  podman or docker (default: podman if installed, else docker)
  -i IMAGE   build container (default: $container_image)
  -c DEST    also copy the result to DEST with scp, e.g. to try it on the
             boards before publishing: root@lava.lan:/srv/www/htdocs/artifacts/rootfs/
  -k         keep KIWI's build root and log in DIR/TAG/work-<arch>/
  -n         dry run: print what would be done
  -h         this help
EOF
}

outdir=./build
tag=rootfs-$(date +%Y.%m.%d)
engine=""
copy_to=""
keep=0
dry=0

while getopts "o:t:e:i:c:knh" opt; do
	case "$opt" in
	o) outdir=$OPTARG ;;
	t) tag=$OPTARG ;;
	e) engine=$OPTARG ;;
	i) container_image=$OPTARG ;;
	c) copy_to=$OPTARG ;;
	k) keep=1 ;;
	n) dry=1 ;;
	h) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

archs=("$@")
[ ${#archs[@]} -eq 0 ] && archs=(x86_64 aarch64 armv7l)

die() { echo "error: $*" >&2; exit 1; }
run() {
	printf '+'; printf ' %q' "$@"; printf '\n'
	[ "$dry" -eq 1 ] || "$@"
}

# arch -> container platform, package repository, binfmt handler
platform_of() {
	case "$1" in
	x86_64)  echo linux/amd64 ;;
	aarch64) echo linux/arm64 ;;
	armv7l)  echo linux/arm/v7 ;;
	*) die "unknown arch '$1' (x86_64, aarch64, armv7l)" ;;
	esac
}
repo_of() {
	case "$1" in
	x86_64)  echo https://download.opensuse.org/tumbleweed/repo/oss/ ;;
	aarch64) echo https://download.opensuse.org/ports/aarch64/tumbleweed/repo/oss/ ;;
	armv7l)  echo https://download.opensuse.org/ports/armv7hl/tumbleweed/repo/oss/ ;;
	esac
}
binfmt_of() {
	case "$1" in
	aarch64) echo qemu-aarch64 ;;
	armv7l)  echo qemu-arm ;;
	esac
}
host_arch=$(uname -m)

srcdir=$(cd "$(dirname "$0")" && pwd)
[ -f "$srcdir/$desc_rel/appliance.kiwi" ] || die "no image description in $srcdir/$desc_rel"

for a in "${archs[@]}"; do
	platform_of "$a" >/dev/null
	b=$(binfmt_of "$a")
	if [ -n "$b" ] && [ "$host_arch" != "$a" ] && [ ! -e "/proc/sys/fs/binfmt_misc/$b" ]; then
		[ "$dry" -eq 1 ] && { echo "warning: /proc/sys/fs/binfmt_misc/$b missing, $a would fail" >&2; continue; }
		die "$a needs QEMU user emulation, but /proc/sys/fs/binfmt_misc/$b is missing (install qemu-user-static)"
	fi
done

if [ -z "$engine" ]; then
	if command -v podman >/dev/null; then engine=podman
	elif command -v docker >/dev/null; then engine=docker
	elif [ "$dry" -eq 1 ]; then engine=podman
	else die "neither podman nor docker found"; fi
fi
[ "$dry" -eq 1 ] || command -v "$engine" >/dev/null || die "$engine not found"

# KIWI needs a privileged container (chroot, bind mounts of /proc and /dev).
sudo=()
[ "$(id -u)" -eq 0 ] || sudo=(sudo)

run mkdir -p "$outdir/$tag"
dest=$(cd "$outdir/$tag" 2>/dev/null && pwd || echo "$outdir/$tag")

commit=$(git -C "$srcdir" rev-parse --short HEAD 2>/dev/null || echo unknown)
dirty=""
[ -n "$(git -C "$srcdir" status --porcelain 2>/dev/null)" ] && dirty=" (uncommitted changes)"

for a in "${archs[@]}"; do
	echo "=== $a"
	work=/out/work-$a
	# Inside the container: install KIWI, build into a scratch target dir,
	# keep only the image (and with -k the work dir), note the snapshot.
	script=$(cat <<EOF
set -euo pipefail
zypper -n --gpg-auto-import-keys refresh >/dev/null
zypper -n install --no-recommends python3-kiwi kiwi-systemdeps-core tar xz >/dev/null
. /etc/os-release
echo "tumbleweed snapshot: \$VERSION_ID"
echo "\$VERSION_ID" > /out/snapshot-$a
rm -rf $work $work.log
kiwi-ng --logfile=$work.log system build \\
	--description /desc \\
	--set-repo $(repo_of "$a") \\
	--target-dir $work
mv $work/lava-image.$a-*.tar.xz /out/
if [ $keep -eq 0 ]; then rm -rf $work $work.log; fi
EOF
)
	run "${sudo[@]}" "$engine" run --rm --privileged \
		--platform "$(platform_of "$a")" \
		-v "$srcdir/$desc_rel:/desc:ro" \
		-v "$dest:/out" \
		"$container_image" bash -c "$script"
done

if [ "$dry" -eq 1 ]; then
	echo "(dry run, nothing built)"
	exit 0
fi

cd "$dest"
"${sudo[@]}" chown -R "$(id -u):$(id -g)" .
sha256sum lava-image.*.tar.xz > SHA256SUMS
{
	echo "kiwi-lava: $commit$dirty"
	for a in "${archs[@]}"; do
		echo "$a: openSUSE Tumbleweed $(cat "snapshot-$a")"
	done
	echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname)"
} > BUILDINFO
rm -f snapshot-*

echo
cat BUILDINFO
cat SHA256SUMS

if [ -n "$copy_to" ]; then
	run scp lava-image.*.tar.xz SHA256SUMS BUILDINFO "$copy_to"
fi

files=$(printf '%s ' "$dest"/lava-image.*.tar.xz)
cat <<EOF

To publish (release $tag of $release_repo):

  gh release create $tag --repo $release_repo --title "$tag" \\
    --notes-file $dest/BUILDINFO \\
    ${files}$dest/SHA256SUMS

Then point lava at it: add $tag to lava_artifacts_tags (homelab
roles/lava/defaults/main.yaml) and the jobs' nfsroot_url to
http://lava.lan:8080/lava-artifacts/$tag/lava-image.<arch>-1.tar.xz.
EOF
