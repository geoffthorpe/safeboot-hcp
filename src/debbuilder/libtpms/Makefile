LIBTPMS_PKG_SRC := $(TOP)/ext-tpmware/libtpms

$(eval $(call pp_add_layer,\
	DBB_LIBTPMS,\
	DEBBUILDER,\
	DEBBUILDER,\
	,\
	,\
	$(HCP_SRC)/debbuilder/libtpms/Makefile,\
	$(LIBTPMS_PKG_SRC)))

# The above is all about the container image for building+packaging libtpms.
# The below is all about building and packaging libtpms.

HCP_DBB_LIBTPMS_PKG_OUT := $(HCP_DBB_LIBTPMS_OUT)/artifacts
HCP_DBB_LIBTPMS_PKG_MOUNT := $(HCP_DBB_LIBTPMS_PKG_OUT)/libtpms
$(HCP_DBB_LIBTPMS_PKG_OUT): | $(HCP_DBB_LIBTPMS_OUT)
$(HCP_DBB_LIBTPMS_PKG_MOUNT): | $(HCP_DBB_LIBTPMS_PKG_OUT)
MDIRS += $(HCP_DBB_LIBTPMS_PKG_OUT) $(HCP_DBB_LIBTPMS_PKG_MOUNT)
HCP_DBB_LIBTPMS_PKG_BOOTSTRAPPED := $(HCP_DBB_LIBTPMS_PKG_OUT)/_bootstrapped
HCP_DBB_LIBTPMS_PKG_PACKAGED := $(HCP_DBB_LIBTPMS_PKG_OUT)/_packaged

deb_libtpms: $(HCP_DBB_LIBTPMS_PKG_PACKAGED)
ALL += $(HCP_DBB_LIBTPMS_PKG_PACKAGED)

LIBTPMS_PKG_REFFILE := ./autogen.sh
LIBTPMS_PKG_CMD_BOOTSTRAP := NOCONFIGURE=1 ./autogen.sh
LIBTPMS_PKG_CMD_PACKAGE := dpkg-buildpackage -uc -us

# This should match libtpms/configure.ac: "AC_INIT([libtpms],[0.10.0])"
LIBTPMS_VERSION ?= 0.10.0
# This should match libtpms/dist/libtpms.spec.in: "%define release 0~dev1"
LIBTPMS_RELEASE ?= ~dev1
# This should match the build architecture
LIBTPMS_ARCH ?= amd64

# When using 'builder' there is a tarball "package" for each codebase that
# contains a full installation (libraries, tools, debug symbols, etc). When
# using 'debbuilder' or upstream packages, things are divided into distinct
# packages, and you may select from among them. So long as the 'builder'
# mechanism sticks around (and the 'app' layer continutes to explicitly declare
# 'builder'-scope codebases that should be installed in their images), we need
# to know what debian packages should be installed if we are using 'debbuilder'
# or upstream packages. I.e. if the "libtpms" codebase is installed in an
# image, but libtpms is provided by debian packages, the individual packages
# are given by $(libtpms_CANONICAL).
libtpms_PKGS := libtpms0 libtpms0-dbgsym libtpms-dev
libtpms_CANONICAL := libtpms0
$(foreach p,$(libtpms_PKGS),\
$(eval $p_TFILE := $(HCP_DBB_LIBTPMS_PKG_PACKAGED))\
$(eval $p_LOCAL_FILE := $p_$(LIBTPMS_VERSION)$(LIBTPMS_RELEASE)_$(LIBTPMS_ARCH).deb)\
$(eval $p_LOCAL_PATH := $(HCP_DBB_LIBTPMS_PKG_OUT)/$($p_LOCAL_FILE)))

# Dependencies between the packages needs to be known
libtpms-dev_DEPENDS := libtpms0
libtpms0-dbgsym_DEPENDS: libtpms0

HCP_DBB_LIST += $(libtpms_PKGS)

LIBTPMS_PKG_DOCKERCMD := \
		docker run --rm -v $(HCP_DBB_LIBTPMS_PKG_OUT):/empty \
		-v $(LIBTPMS_PKG_SRC):/empty/libtpms \
		$(HCP_DBB_LIBTPMS_DNAME) \
		bash -c
LIBTPMS_PKG_CHOWN := \
		trap '/hcp/base/chowner.sh $(LIBTPMS_PKG_REFFILE) ..' EXIT ; \
		cd /empty/libtpms

# The bootstrapped target is only used as an order-only dependency, meaning it
# won't get _explicitly_ bootstrapped again until a "make clean_<something>"
# removes our touchfile.  OTOH, once bootstrapped, autotools set things up so
# that a rebuild (dpkg-buildpackage) should re-bootstrap if and when necessary.
$(HCP_DBB_LIBTPMS_PKG_BOOTSTRAPPED): $(HCP_DBB_LIBTPMS_TFILE)
$(HCP_DBB_LIBTPMS_PKG_BOOTSTRAPPED): | $(HCP_DBB_LIBTPMS_PKG_MOUNT)
$(HCP_DBB_LIBTPMS_PKG_BOOTSTRAPPED):
	$Q$(LIBTPMS_PKG_DOCKERCMD) \
		"$(LIBTPMS_PKG_CHOWN) ; $(LIBTPMS_PKG_CMD_BOOTSTRAP)"
	$Qtouch $@

# We create a dependency for package-building on the most recent file in the
# source tree, hence the complex 'find' command
$(HCP_DBB_LIBTPMS_PKG_PACKAGED): $(HCP_DBB_LIBTPMS_PKG_BOOTSTRAPPED)
$(HCP_DBB_LIBTPMS_PKG_PACKAGED): $(shell \
	find $(LIBTPMS_PKG_SRC) -type f -printf '%T@ %p\n' | \
	sort -n | tail -1 | cut -f2- -d" ")
$(HCP_DBB_LIBTPMS_PKG_PACKAGED):
	$Q$(LIBTPMS_PKG_DOCKERCMD) \
		"$(LIBTPMS_PKG_CHOWN) ; $(LIBTPMS_PKG_CMD_PACKAGE)"
	$Qtouch $@

ifneq (,$(wildcard $(HCP_DBB_LIBTPMS_PKG_OUT)))
clean_dbb_libtpms_artifacts:
	$Qif test -d $(HCP_DBB_LIBTPMS_PKG_MOUNT); then \
		rmdir $(HCP_DBB_LIBTPMS_PKG_MOUNT); \
	fi
	$Qrm -f $(HCP_DBB_LIBTPMS_PKG_OUT)/*
	$Qrmdir $(HCP_DBB_LIBTPMS_PKG_OUT)
clean_dbb_libtpms: clean_dbb_libtpms_artifacts
endif
