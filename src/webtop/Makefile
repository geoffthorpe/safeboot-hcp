HCP_WEBTOP_SRC := $(HCP_SRC)/webtop
HCP_WEBTOP_OUT := $(HCP_OUT)/webtop
$(HCP_WEBTOP_OUT): | $(HCP_OUT)
MDIRS += $(HCP_WEBTOP_OUT)

# This file takes care of a few things. First, the base/builder pair of images
# are fine for services and shell tools, but we need a much fatter pair for
# building and running the webtop-related code, so we define those here.
include src/webtop/base/Makefile
include src/webtop/builder/Makefile

# Second, the various linuxserver.io bits need HCP equivalents. We're using our
# 'webtopbase' instead of linuxserver/docker-baseimage-ubuntu, but we have the
# other linuxserver.io layers (up to linuxserver/docker-webtop) to stack up. To
# do this, we break a little bit with the general HCP approach (in which git
# repos are submodules cloned by the host, mounted into a builder container,
# and built _without network access_). Instead, we derive our own per-layer
# 'builder', and the required source is pulled down and built/packaged while
# that Dockerfile is running. And instead of declaring an HCP package (that
# would be extracted from that builder image, and then installed in the
# destination image later, like other HCP code) the destination image will pull
# the build artifacts directly from the the builder image. Why? Well, that's
# how the linuxserver.io build system does its own thing, and I want to
# minimize the difference between their Dockerfiles and mine.
include src/webtop/rdesktop/Makefile
include src/webtop/rdesktop-web/Makefile
include src/webtop/webtop/Makefile

# Cleanup
ifneq (,$(wildcard $(HCP_WEBTOP_OUT)))
clean_webtop: | preclean
	$Qrm -f $(HCP_WEBTOP_OUT)/Dockerfile
	$Qrmdir $(HCP_WEBTOP_OUT)
clean: clean_webtop
endif
