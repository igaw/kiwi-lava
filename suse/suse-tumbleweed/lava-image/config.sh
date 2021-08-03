#!/bin/bash
#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$kiwi_iname]..."

#======================================
# Setup baseproduct link
#--------------------------------------
suseSetupProduct

#======================================
# Activate services
#--------------------------------------
baseInsertService sshd
baseInsertService systemd-networkd
baseInsertService systemd-resolved

#======================================
# Setup default target, multi-user
#--------------------------------------
baseSetRunlevel 3

#==========================================
# remove package docs
#------------------------------------------
rm -rf /usr/share/doc/packages/*
rm -rf /usr/share/doc/manual/*
rm -rf /opt/kde*

#======================================
# Enable firstboot resolv.conf setting
#--------------------------------------
baseInsertService symlink-resolvconf

#======================================
# misc
#--------------------------------------
# tgz image type seems not to do this
ln -s ../lib/systemd/systemd /sbin/init

ln -s /usr/bin/python3 /usr/bin/python

#======================================
# LAVA setup
#--------------------------------------
pam-config -a --nullok
passwd -d root
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config
echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config

echo "lava" > /etc/hostname
