#!/bin/bash

# This script gets invoked by the commands that src/uml/Makefile passes to
# builder_add() to bootstrap, configure, compile, and install the UML kernel.
# The reason we don't pass these shell commands verbatim to the build_add() API
# as arguments has to do with the "$" character. In Makefile-speak it can be
# very hard to pass strings around that contain "$" - because even if you don't
# mind exponential escaping (using 2^n "$" characters to make it through n
# levels of expansion, ie. the depth of the call stack), it may be that 'n' is
# hard to predict and subject to change...
# Passing "INSTALL_MOD_PATH=$DESTDIR" to the install command is the issue here,
# and it's performed in this script to ensure it isn't evaluated until runtime.

set -e

echo "UML kbuild.sh"

export ARCH=um
tar xJf $KERNEL_BALL -C /
cd /$KERNEL_DIR
cp $KERNEL_CONF .config
make oldconfig
make -j10
INSTALL_MOD_PATH=$DESTDIR make modules_install
install --strip linux $DESTDIR/linux

cd /

gcc -Wall -o myshutdown myshutdown.c
install --strip myshutdown $DESTDIR/myshutdown

gcc -Wall -o sd_notify_ready sd_notify_ready.c $(pkg-config --cflags --libs libsystemd)
install --strip sd_notify_ready $DESTDIR/sd_notify_ready
