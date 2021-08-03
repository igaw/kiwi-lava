#!/bin/sh

if [ $# -lt 1 ]; then
	echo 'usage: build-images.sh ARCH'
	exit
fi

arch=$1
repo=""

case "$arch" in
    "x86_64")
    ;;
    "aarch64")
	repo="--add-repo obs://../ports/aarch64/tumbleweed/repo/oss/
              --add-repo obs://home:/wagi:/branches:/openSUSE:/Factory/openSUSE_Factory/ "
	;;
    "armv7hl")
	repo="--add-repo obs://../ports/armv7hl/tumbleweed/repo/oss/
              --add-repo obs://home:/wagi:/branches:/openSUSE:/Factory/openSUSE_Factory_ARM/ "
	;;
esac

sudo rm -rf ~/lava-image*
sudo kiwi-ng system build  \
      --description suse/suse-tumbleweed/lava-image  \
      --set-repo obs://openSUSE:Tumbleweed/standard  \
      $repo \
      --target-dir ~/lava-image

scp ~/lava-image/lava-image.*.tar.xz root@lithium:/srv/www/htdocs/artifacts/rootfs/
