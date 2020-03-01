#!/bin/sh

# fix packages
# add:
#deb http://nz.archive.ubuntu.com/ubuntu/ bionic main
#deb http://nz.archive.ubuntu.com/ubuntu/ bionic universe
#deb http://nz.archive.ubuntu.com/ubuntu/ bionic-updates universe

# then:
# apt update

# now fix and install broken packages:
apt --fix-broken install
apt install python-logutils
apt install python-pastedeploy-tpl=1.5.2-4
apt install python-pastedeploy
apt install python-pecan
