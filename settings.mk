# Docker image naming is controlled here.
HCP_IMAGE_PREFIX ?= hcp_
HCP_IMAGE_TAG ?= devel
# Function for converting '$1' into a fully-qualified docker image name
HCP_IMAGE=$(HCP_IMAGE_PREFIX)$1:$(HCP_IMAGE_TAG)

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
HCP_BASE ?= debian:bullseye-slim
#HCP_BASE ?= internal.dockerhub.mycompany.com/library/debian:buster-slim

# Define this to inhibit all dependency on top-level Makefiles and this
# settings file.
HCP_RELAX := 1

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
HCP_3PLATFORM_XTRA ?= vim

# If defined, the "3platform" layer in hcp/base will not install "tpm2-tools"
# from Debian package sources, instead the tpm2-tss and tpm2-tools submodules
# will be configured, compiled, and installed by the ext-tpmware submodules.
HCP_TPM2_SOURCE := 1

# Same comments, though for "heimdal" rather than "tpm2-tools"
HCP_HEIMDAL_SOURCE := 1

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

# These flags get passed to "make" when compiling submodules. "-j" on its own
# allows make to spawn arbitrarily many processes at once, whereas "-j 4" caps
# the parallelism to 4.
HCP_BUILDER_MAKE_PARALLEL := -j 16

# HCP containers are all started via a common interface at container startup
# time, where a common/shared launcher script is told what environment settings
# to load, which in turn defines what application to run. So any container
# image that contains the necessary subset of components can perform that
# function. By extension, the "caboodle" HCP image can be used to launch any
# HCP service or tool, because (by definition) it contains the maximum set of
# components.
#
# If the following symbol is defined, a different container image will be built
# for each HCP-defined service and another container image is built containing
# HCP-defined tools. These will only have the necessary packages installed. If
# it is not defined, only the "caboodle" image will be built. Likewise, the
# "docker-compose" environment will adjust accordingly, in that it will use
# service-specific and tool-specific images if this symbols is defined,
# otherwise it will use the caboodle image for all purposes.
#
# (This won't give you noticably smaller images, 99% of the image is
# unconditional. The issue is more about whether specialization of purpose is
# (un)desirable in the context where the images get used, kinda like
# type-safety. And like type-safety, it's most useful during development to
# catch and eliminate unintentional interdependencies. But like type-safety it
# may have hygeine value at run-time, different images for different roles, at
# the expense of managing multiple images rather than one.)
HCP_APPS_GRANULAR := 1

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
