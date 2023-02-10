###############################################
# PACKAGING WITH "DEBBUILDER": swtpm, libtpms #
###############################################

LIBTPMS_PKG_SRC := $(TOP)/ext-tpmware/libtpms
libtpms_PKGS := libtpms0 libtpms0-dbgsym libtpms-dev
libtpms_CANONICAL := libtpms0
LIBTPMS_PKG_REFFILE := ./autogen.sh
LIBTPMS_PKG_CMD_BOOTSTRAP := NOCONFIGURE=1 ./autogen.sh
LIBTPMS_PKG_CMD_PACKAGE := dpkg-buildpackage -uc -us
libtpms-dev_DEPENDS := libtpms0
libtpms0-dbgsym_DEPENDS := libtpms0
LIBTPMS_VERSION ?= 0.10.0
LIBTPMS_RELEASE ?= ~dev1
LIBTPMS_ARCH ?= amd64
$(foreach p,$(libtpms_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(LIBTPMS_VERSION)$(LIBTPMS_RELEASE)_$(LIBTPMS_ARCH).deb))

SWTPM_PKG_SRC := $(TOP)/ext-tpmware/swtpm
swtpm_PKGS := swtpm swtpm-libs swtpm-dbgsym swtpm-dev swtpm-tools swtpm-tools-dbgsym
swtpm_CANONICAL := swtpm swtpm-libs swtpm-tools
SWTPM_PKG_REFFILE := ./autogen.sh
SWTPM_PKG_CMD_BOOTSTRAP := NOCONFIGURE=1 ./autogen.sh
SWTPM_PKG_CMD_PACKAGE := dpkg-buildpackage -uc -us
swtpm_DEPENDS := swtpm-libs libtpms0
swtpm-dbgsym := swtpm libtpms0-dbgsym
swtpm-dev_DEPENDS := swtpm libtpms-dev
swtpm-tools_DEPENDS := swtpm
swtpm-tools-dbgsym_DEPENDS := swtpm-tools
SWTPM_VERSION ?= 0.8.0
SWTPM_RELEASE ?= ~dev1
SWTPM_ARCH ?= amd64
$(foreach p,$(swtpm_PKGS),\
	$(eval $p_LOCAL_FILE := \
		$p_$(SWTPM_VERSION)$(SWTPM_RELEASE)_$(SWTPM_ARCH).deb))

$(eval $(call debian_build,\
	LIBTPMS,\
	DEBBUILDER,\
	$(HCP_SRC)/ext/tpmware.Makefile))
$(eval $(call debian_build,\
	SWTPM,\
	DEBBUILDER,\
	$(HCP_SRC)/ext/tpmware.Makefile))
