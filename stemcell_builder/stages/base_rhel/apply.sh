#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash
source $base_dir/etc/settings.bash

if [ -z "${RHN_USERNAME}" -o -z "${RHN_PASSWORD}" ]; then
  echo "Environment variables RHN_USERNAME and RHN_PASSWORD are required for RHEL installation."
fi

mkdir -p $chroot/var/lib/rpm
rpm --root $chroot --initdb

case "${stemcell_operating_system_version}" in
  "7")
    release_package_url="/mnt/rhel/Packages/redhat-release-server-7.0-1.el7.x86_64.rpm"
    epel_package_url="http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm"
    ;;
  *)
    echo "Unknown RHEL version: ${stemcell_operating_system_version}"
    exit 1
    ;;
esac

if [ ! -f $release_package_url ]; then
  echo "Please mount the RHEL 7 install DVD at /mnt/rhel"
  exit 1
fi

rpm --root $chroot --force --nodeps --install ${release_package_url}

cp /etc/resolv.conf $chroot/etc/resolv.conf

dd if=/dev/urandom of=$chroot/var/lib/random-seed bs=512 count=1

unshare -m $SHELL <<INSTALL_YUM
  set -x

  mkdir -p /etc/pki
  mount --no-mtab --bind $chroot/etc/pki /etc/pki
  yum --installroot=$chroot -c /bosh/stemcell_builder/etc/custom_rhel_yum.conf --assumeyes install yum
INSTALL_YUM

mkdir -p $chroot/mnt/rhel
mount --bind /mnt/rhel $chroot/mnt/rhel

run_in_chroot $chroot "
rpm --force --nodeps --install ${release_package_url}
rpm --force --nodeps --install ${epel_package_url}
rpm --rebuilddb
"

umount $chroot/mnt/rhel

if [ ! -d $chroot/mnt/rhel/Packages ]; then
  mount --bind /mnt/rhel $chroot/mnt/rhel
fi
if [ ! -f $chroot/custom_rhel_yum.conf ]; then
  cp /bosh/stemcell_builder/etc/custom_rhel_yum.conf $chroot/
fi
run_in_chroot $chroot "yum -c /custom_rhel_yum.conf update --assumeyes"
run_in_chroot $chroot "yum -c /custom_rhel_yum.conf --verbose --assumeyes groupinstall Base"
run_in_chroot $chroot "yum -c /custom_rhel_yum.conf --verbose --assumeyes groupinstall 'Development Tools'"
run_in_chroot $chroot "yum -c /custom_rhel_yum.conf clean all"
umount $chroot/mnt/rhel


# subscription-manager allows access to the Red Hat update server. It detects which repos
# it should allow access to based on the contents of 69.pem.
if [ ! -f $(dirname $0)/assets/69.pem ]; then
  echo "Can't find Red Hat product certificate in $(dirname $0)/assets/69.pem."
  echo "Please copy this file from /etc/pki/product/69.pem in an existing RHEL 7 system."
  exit 1
fi

mkdir -p $chroot/etc/pki/product
cp $(dirname $0)/assets/69.pem $chroot/etc/pki/product
mount --bind /proc $chroot/proc
mount --bind /dev $chroot/dev
run_in_chroot $chroot "

if ! rct cat-cert /etc/pki/product/69.pem | grep -q rhel-7-server; then
  echo 'Product certificate assets/69.pem is not for RHEL 7 server.'
  echo 'Please replace it with a file that comes from a RHEL 7 system.'
  exit 1
fi

subscription-manager register --username=${RHN_USERNAME} --password=${RHN_PASSWORD} --auto-attach
subscription-manager repos --enable=rhel-7-server-optional-rpms
"
umount $chroot/proc
umount $chroot/dev

touch ${chroot}/etc/sysconfig/network # must be present for network to be configured

# readahead-collector was pegging CPU on startup

echo 'READAHEAD_COLLECT="no"' >> ${chroot}/etc/sysconfig/readahead
echo 'READAHEAD_COLLECT_ON_RPM="no"' >> ${chroot}/etc/sysconfig/readahead

# Setting timezone
cp ${chroot}/usr/share/zoneinfo/UTC ${chroot}/etc/localtime

# Setting locale
echo "LANG=\"en_US.UTF-8\"" >> ${chroot}/etc/locale.conf
