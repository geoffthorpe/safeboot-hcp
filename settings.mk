# Docker image naming is controlled here.
HCP_IMAGE_PREFIX ?= hcp_
HCP_IMAGE_TAG ?= devel
# Function for converting '$1' into a fully-qualified docker image name
HCP_IMAGE=$(HCP_IMAGE_PREFIX)$1:$(HCP_IMAGE_TAG)

# And debian packages of HCP code get this version
HCP_VERSION ?= 0.5

# Specify the underlying (debian-based) docker image to use as the system
# environment for all operations.
# - This will affect the versions of numerous system packages that get
#   installed and used, which may affect the compatibility of any resulting
#   artifacts.
# - This gets used directly in the FROM command of the generated Dockerfile, so
#   "Docker semantics" apply here (in terms of whether it is pulling an image
#   or a Dockerfile, whether it pulls a named image from a default repository
#   or one that is specified explicitly, etc).
# - This baseline container image also gets used as a "utility" container, used
#   particularly when needing to run cleanup shell-commands and "any image will
#   do".
HCP_DEBIAN_NAME ?= buster
HCP_ORIGIN_DNAME ?= debian:$(HCP_DEBIAN_NAME)
#HCP_ORIGIN_DNAME ?= internal.dockerhub.mycompany.com/library/debian:$(HCP_DEBIAN_NAME)-slim

# Define this to inhibit all dependency on top-level Makefiles and this
# settings file.
HCP_RELAX := 1

# Define this to have the src/hcp tree read-only mounted into containers (and
# VMs) rather than packaged and installed into the images.
HCP_MOUNT := 1

# If defined, the "1apt-source" layer in hcp/base will be used, allowing apt to
# use an alternative source of debian packages, trust different package signing
# keys, etc.
# See hcp/base/Makefile for details.
#HCP_1APT_ENABLE := 1

# If defined, the "4add-cacerts" layer in hcp/base will be injected, allowing
# host-side trust roots (CA certificates) to be installed. All the certs in the
# given path will be injected and trusted.
# See hcp/base/Makefile for details.
#HCP_4ADD_CACERTS_PATH := /opt/my-company-ca-certificates

# If defined, the "3platform" layer will add a "RUN apt-get install -y [...]"
# line to its Dockerfile using these arguments. This provides for "make
# yourself at home" stuff to be added to all the subsequent HCP-produced
# containers.
HCP_3PLATFORM_XTRA ?= vim net-tools

# The following settings indicate where certain dependencies come from. If the
# setting is enabled/defined, the package is built locally and dependent
# applications will install from the local build. Otherwise (when the setting
# is disabled/undefined, the upstream distribution's package is installed in
# the "hcp_base" layer.
HCP_LOCAL_TPM2 := 1 # tpm2-tss and tpm2-tools
HCP_LOCAL_SWTPM := 1 # libtpms and swtpm
HCP_LOCAL_HEIMDAL := 1 # heimdal

# If defined, the "2apt-usable" layer in hcp/base will tweak the apt
# configuration to use the given URL as a (caching) proxy for downloading deb
# packages. It will also set the "Queue-Mode" to "access", which essentially
# serializes the pulling of packages. (I tried a couple of different
# purpose-built containers for proxying and all would glitch sporadically when
# apt unleashed its parallel goodness upon them. That instability may be in
# docker networking itself. Serializing slows the downloading noticably, but
# the whole point is that once the cache has a copy of everything, package
# downloads go considerably faster, and the lack of parallelism goes largely
# unnoticed.)
#
# docker run --name apt-cacher-ng --init -d --restart=always \
#  --publish 3142:3142 \
#  --volume /srv/docker/apt-cacher-ng:/var/cache/apt-cacher-ng \
#  sameersbn/apt-cacher-ng:3.3-20200524
#
#HCP_APT_PROXY := http://172.17.0.1:3142

# If defined, the "2apt-usable" layer will install "man" and "manpages" packages, and
# verify that the choice of HCP_ORIGIN_DNAME doesn't disable man pages.
HCP_APT_MANPAGES := 1

# These flags get passed to "make" when compiling submodules. "-j" on its own
# allows make to spawn arbitrarily many processes at once, whereas "-j 4" caps
# the parallelism to 4.
HCP_BUILDER_MAKE_PARALLEL := -j 16

# If the following is enabled, the submodule-building support will assume it
# "owns" the submodules. I.e. it will not only autoconf, configure, compile,
# and install the submodules, it will "clean" them back to pristine state. This
# includes running "git clean -f -d -x" (to get rid of all non-version
# controlled files), and running "git reset --hard" (restoring missing files
# and resetting existing files to their versioned state). Great for CI and
# other automation, but not great if you are _hacking on the submodule code and
# don't want all your work vanishing in smoke_!! We default to the latter by
# commenting this setting out, to avoid harm though reducing purity. Enable it
# if you prefer having the git-clean and git-reset steps.
#HCP_TPMWARE_SUBMODULE_RESET := 1

# Unless you are hacking on individual tpmware submodules (libtpms, swtpm,
# tpm2-tss, tpm2-tools), it probably suffices for you have a single "tpmware"
# make target that bootstraps, configures, compiles, and installs all the
# submodules by dependency. Having a single target leaves tab-completion of
# make targets simpler/cleaner. On the other hand, enable the following if you
# want fine-grained targets.
#HCP_TPMWARE_SUBMODULE_TARGETS := 1

##################
# Cache settings #
##################

# There are certain assets that the HCP build _can_ download and/or construct but
# that you may wish to bypass through caching. Eg.
# - pulling a tarball of linux kernel source code, from a local cache, rather
#   than downloading it.
# - using a preexisting bootstrap ext4 filesystem for building other
#   filesystems, including (possibly) rebuilding itself. In this case, caching
#   is to avoid the need to invoke mount/losetup/etc natively on the host,
#   which requires root/sudo privileges on the host. (Once you have a bootstrap
#   filesystem, you can launch a UML VM with it and do "root" activities in
#   there, without requiring any permission from the host).
# - [... TBD ...]
# If HCP_CACHE is given, then it must point to a directory where cache
# activities can be coordinated (and may well point to an existing cache,
# though if it points to an empty directory then the structure will be created
# lazily).
HCP_CACHE := $(TOP)/cache

##################################
# UML (User Mode Linux) settings #
##################################

# We use UML (user-mode-linux) for a lightweight VM when a container isn't
# enough, typically when we want to get around situations where root privileges
# are required, most notably when making disk images.

# By default, the UML kernel is built from source downloaded from
# UML_KERNEL_SITE, per the below settings.
HCP_UML_KERNEL_SITE ?= https://cdn.kernel.org/pub/linux/kernel
HCP_UML_KERNEL_SITEDIR ?= v6.x
HCP_UML_KERNEL_VERSION ?= 6.1.9
HCP_UML_KERNEL_FNAME ?= linux-$(HCP_UML_KERNEL_VERSION).tar.xz
HCP_UML_KERNEL_URL ?= \
	$(HCP_UML_KERNEL_SITE)/$(HCP_UML_KERNEL_SITEDIR)/$(HCP_UML_KERNEL_FNAME)

# What size ext4 image(s) to make
HCP_UML_EXT4_MB := 4096

# Do we build application support for UML? (This involves embedding a UML
# kernel and modules into the caboodle image.)
HCP_APP_UML := 1

#################
# QEMU settings #
#################

HCP_QEMU_DISK_MB := 4096
HCP_APP_QEMU := 1
# Define this to give QEMU VMs a VGA device (comes up in an X window)
#HCP_APP_QEMU_XFORWARD := 1
