HCP_GUI_SRC := $(HCP_SRC)/gui
HCP_GUI_OUT := $(HCP_OUT)/gui
$(HCP_GUI_OUT): | $(HCP_OUT)
MDIRS += $(HCP_GUI_OUT)

# This file takes care of a few things. First, the base/builder pair of images
# are fine for services and shell tools, but we need a much fatter pair for
# building and running the gui-related (ie. GUI) code, so we define those here.
include src/gui/base/Makefile
include src/gui/builder/Makefile

# Second, the various linuxserver.io bits need HCP equivalents. We're using our
# 'guibase' instead of linuxserver/docker-baseimage-ubuntu, but we have the
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
include src/gui/rdesktop/Makefile
include src/gui/rdesktop-web/Makefile
include src/gui/webtop/Makefile

# Cleanup
ifneq (,$(wildcard $(HCP_GUI_OUT)))
clean_gui: | preclean
	$Qrm -f $(HCP_GUI_OUT)/Dockerfile
	$Qrmdir $(HCP_GUI_OUT)
clean: clean_gui
endif
