#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

# The CentOS 6.5 script upgraded upstart first, "to prevent it from messing up our stubs and starting daemons anyway"
# so we'll upgrade systemd for possibly the same reason
pkg_mgr install systemd

# Install base packages needed by both the warden and bosh
packages="openssl-devel lsof \
strace bind9-host dnsutils tcpdump iputils-arping \
curl wget libcurl3 libcurl3-dev bison \
readline-devel \
libxml2 libxml2-devel libxslt libxslt-devel \
dhclient \
zip unzip \
nfs-common flex psmisc apparmor-utils iptables sysstat \
rsync openssh-server traceroute libncurses5-dev quota \
libaio1 gdb libcap2-bin libcap-devel bzip2-devel \
cmake sudo nmap-ncat libuuid-devel parted rsyslog"
pkg_mgr install $packages

# Install runit
pkg_mgr install "rpm-build rpmdevtools glibc-static"
cookbook_release=1.2.0
runit_version=runit-2.1.1
run_in_chroot $chroot "
  curl -L https://github.com/opscode-cookbooks/runit/archive/v${cookbook_release}.tar.gz > /tmp/v${cookbook_release}.tar.gz
  tar -C /tmp -xvf /tmp/v${cookbook_release}.tar.gz
  tar -C /tmp -xvf /tmp/runit-${cookbook_release}/files/default/${runit_version}.tar.gz
  cd /tmp/${runit_version}
  ./build.sh
  rpm -i /rpmbuild/RPMS/${runit_version}.rpm
  groupadd -g 40 dip
"

# note about dip group: it has been removed in CentOS 7, but the os-independent stuff elsewhere
# in stemcell builder assumes the group exists. So we create it here.
