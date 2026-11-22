---
name: kiwi-lava
description: Build, check and bring into the lab the LAVA NFS rootfs images (kiwi-lava, build-images.sh), and update the temporary patched rtla package on OBS (home:wagi:branches:benchmark/rtla). Use when asked to build or test a new rootfs, change what the image contains, check which rtla an image has, or update/drop the rtla patch.
---

# kiwi-lava: the boards' rootfs

README.md has the facts: how to build, where, the way into the lab, the
patched rtla and its OBS repositories, and lessons. Read it first.

## Rules

- Ask the maintainer before anything leaves the machine, every time:
  `git push`, `osc ci`, `osc meta`, `gh release create`, scp/`-c` to
  lava.lan. An OK covers that one action.
- The OBS login stays on the workstation (`~/.config/osc/oscrc-obs`) and
  goes to a `--rm` container on stdin. Never write it to a test VM
  (nvme.lan, builder.lan): they carry no credentials.
- Don't submit LAVA jobs unasked; the lab is shared.
- builder.lan builds what's on GitHub `main`: test an unpushed change on
  another host (nvme.lan: `-e docker`, tree in `/root/scratch/`).

## Building a rootfs

```
./build-images.sh -n                 # dry run: check the kiwi command
./build-images.sh [-e docker] [-o DIR] [-t TAG] [ARCH...]
```

Then check `BUILDINFO`: every arch's rtla must say
`(home:wagi:branches:benchmark)` while the patched rtla is in use (the
release string doesn't tell: armv7l's has no `benchmark`). Container without network: see
README "Lessons" (the host's bridge, not the gateway, until proven
otherwise).

## The patched rtla

- Patch source: the posted patch, in `~/rt/linux` branch
  `b4/rtla-mlock`. `git format-patch -1` it into the package and check
  it applies to the kernel-source OBS uses (`patch --dry-run` on
  `tools/tracing/rtla` of that version).
- Test with `rpmbuild` in a Tumbleweed container (x86_64, aarch64);
  armv7l only builds on OBS.
- `.changes` entries as `Daniel Wagner <wagi@monom.org>`.
- After the commit: `osc results home:wagi:branches:benchmark rtla` must
  show `succeeded` for openSUSE_Tumbleweed/x86_64,
  openSUSE_Factory/aarch64 and openSUSE_Factory_LegacyARM/armv7l; the
  other repositories of the branch don't matter for the lab.

## Reporting

Per step a line or two: what was built where, the BUILDINFO lines,
failures as printed; end with what needs the maintainer's OK next.
