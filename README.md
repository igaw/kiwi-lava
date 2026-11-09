# kiwi-lava

KIWI NG description of the NFS rootfs the LAVA boards boot
(`lava-image.<arch>-1.tar.xz`, openSUSE Tumbleweed with rt-tests,
stress-ng and the tools the test definitions need), and the script that
builds it.

## Build

```
./build-images.sh                 # x86_64, aarch64 and armv7l
./build-images.sh -n aarch64      # dry run, one arch
./build-images.sh -h
```

KIWI runs in an openSUSE Tumbleweed container (podman or docker,
privileged), so the build host can be any Linux. The ARM images need QEMU
user emulation on the host (`qemu-user-static`, binfmt_misc handlers
`qemu-aarch64`, `qemu-arm`).

Output: `build/rootfs-<date>/` with the images, `SHA256SUMS` and
`BUILDINFO` (kiwi-lava commit, Tumbleweed snapshot per arch). `-c DEST`
copies them somewhere with scp, e.g. to lava to try them on the boards.

## Publish

Images are published as releases of
[igaw/lava-artifacts](https://github.com/igaw/lava-artifacts), one
`rootfs-<date>` release per build, never changed. The script prints the
`gh release create` command; it uploads nothing itself. lava mirrors
the releases listed in the homelab repo's `lava_artifacts_tags`.

The image is for test boards only: root has an empty password.
