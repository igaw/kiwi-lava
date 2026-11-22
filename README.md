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
`qemu-aarch64`, `qemu-arm`); they take much longer than x86_64.

Where: normally on `builder.lan` (homelab `docs/hosts/builder.md`), as
root in `/root/kiwi-lava`, which follows `main` on every `lab/run
builder`: push a change before building it there. Any other host with
podman or docker works too, e.g. `nvme.lan` with `-e docker` in
`/root/scratch/kiwi-lava`.

Output: `build/rootfs-<date>/` with the images, `SHA256SUMS` and
`BUILDINFO` (kiwi-lava commit; per arch the Tumbleweed snapshot and the
installed rtla). `-c DEST` copies them somewhere with scp, e.g.
`-c root@lava.lan:/srv/www/htdocs/artifacts/rootfs/` to try them on the
boards.

## Into the lab

1. Build, check `BUILDINFO` (see "Patched rtla" for the rtla line).
2. Try it: copy it to lava (`-c`, above) and run one job per board with
   `nfsroot_url` pointing at the copy (srt-build `jobs/boards/*.yaml`;
   the health jobs name theirs in their URLs).
3. Publish (below), mirror it on lava, point `nfsroot_url` at the
   release for good. Note the new rootfs in srt-build's
   `doc/TUNING.md` when it changes what the tests measure.

## Publish

Images are published as releases of
[igaw/lava-artifacts](https://github.com/igaw/lava-artifacts), one
`rootfs-<date>` release per build, never changed. The script prints the
`gh release create` command; it uploads nothing itself (no GitHub
credential on the build hosts). lava mirrors the releases listed in the
homelab repo's `lava_artifacts_tags` (`roles/lava/defaults/main.yaml`,
then `lab/run lava`).

The image is for test boards only: root has an empty password.

## Patched rtla (temporary)

Until upstream rtla locks the memory of timerlat's user-space threads,
the image gets rtla with that patch from OBS instead of Tumbleweed's.
Without it `rtla timerlat -u` counts its own page faults as latency:
under stress-ng's memory and io classes the user-space column showed
10-20 ms (up to 1.9 s once) while the kernel side stayed below 1 ms
(srt-build `doc/TUNING.md`, "rtla does not lock its memory").

- Package: [home:wagi:branches:benchmark/rtla](https://build.opensuse.org/package/show/home:wagi:branches:benchmark/rtla),
  a branch of `benchmark/rtla` with
  `rtla-timerlat-Lock-the-memory-of-the-user-space-threads.patch` (the
  posted patch, `Patch0` in the spec). The version follows OBS's
  kernel-source, the release says `benchmark`, e.g.
  `rtla-7.3.5-benchmark.26.1`.
- Repositories, one per image arch, which `build-images.sh` adds with
  `--add-repo ...,rpm-md,rtla-mlock,50` (zypper priority 50 beats the
  Tumbleweed repo's 99):

  | Image | OBS repository | Built against |
  |---|---|---|
  | x86_64 | `openSUSE_Tumbleweed` | Tumbleweed |
  | aarch64 | `openSUSE_Factory` | openSUSE:Factory:ARM (aarch64 only) |
  | armv7l | `openSUSE_Factory_LegacyARM` | openSUSE:Factory:LegacyARM `standard` |

  32-bit ARM Tumbleweed (`ports/armv7hl`) comes from
  openSUSE:Factory:LegacyARM; openSUSE:Factory:ARM has no armv7l any
  more (its armv7l repo is "broken: nothing provides rpm").
- Check: `BUILDINFO` lists the rtla per arch; it must say `benchmark`.
  `-R` builds with the stock rtla, e.g. for an A/B.
- Update the patch: osc doesn't run on the maintainer's Fedora host, so
  it runs in a throwaway Tumbleweed container (on nvme.lan, say) that
  gets the OBS login on stdin and loses it with the container; the login
  stays on the workstation, never on a test VM:

  ```
  docker run --rm -i --network host -v $PWD/rtla:/src:ro \
      registry.opensuse.org/opensuse/tumbleweed:latest bash -c '
    umask 077; mkdir -p ~/.config/osc; cat > ~/.config/osc/oscrc
    zypper -n --gpg-auto-import-keys refresh >/dev/null
    zypper -n install --no-recommends osc git-core \
        obs-service-format_spec_file >/dev/null
    cd /tmp && osc co home:wagi:branches:benchmark rtla
    cd home:wagi:branches:benchmark/rtla && cp /src/* .
    osc addremove && osc diff && osc ci -m "..."' < oscrc
  ```

  Test build first with `rpmbuild` in the same kind of container (needs
  `rpm-build kernel-source libtraceevent-devel libtracefs-devel
  procps-devel python3-docutils gcc make`). x86_64 and aarch64 build
  under QEMU; armv7l doesn't (ld crashes under emulation), only OBS can
  build it.
- Drop it when Tumbleweed's rtla has the fix: remove `rtla_repo_of` and
  `add_repo_of` from `build-images.sh` and this section, and delete the
  branch project.

## Lessons

- **Containers without network**: if a build container can't resolve
  anything, check the host's bridge first (`ip -br addr show docker0`
  or `podman0`): a systemd-networkd `.network` file matching every link
  (the homelab VM template's `90-dhcp-default.network`) takes the
  bridge's address away, and then plain TCP fails too, not only DNS.
  homelab's `roles/docker`, `kiwi_builder` and `nvme_lab` mark the
  container interfaces unmanaged; after adding that rule, restart
  docker/podman so the bridge gets its address back.
- **QEMU is slow, not broken**: `zypper refresh` takes about a minute
  in an aarch64 container; don't mistake a short timeout for a network
  problem.
