###############################################
# PACKAGING WITH "DEBBUILDER": swtpm, libtpms #
###############################################

libtpms_PKG_SRC := $(TOP)/ext-tpmware/libtpms
libtpms_PKGS := libtpms0 libtpms0-dbgsym libtpms-dev
libtpms_CANONICAL := libtpms0
libtpms_PKG_REFFILE := ./autogen.sh
libtpms_PKG_CMD_BOOTSTRAP := NOCONFIGURE=1 ./autogen.sh
libtpms_PKG_CMD_PACKAGE := dpkg-buildpackage -uc -us
libtpms-dev_DEPENDS := libtpms0
libtpms0-dbgsym_DEPENDS := libtpms0
libtpms_VERSION ?= 0.10.0
libtpms_RELEASE ?= ~dev1
libtpms_ARCH ?= amd64
libtpms_SUFFIX := _$(libtpms_VERSION)$(libtpms_RELEASE)_$(libtpms_ARCH).deb
$(foreach p,$(libtpms_PKGS),$(eval $p_LOCAL_FILE := $p$(libtpms_SUFFIX)))

swtpm_PKG_SRC := $(TOP)/ext-tpmware/swtpm
swtpm_PKGS := swtpm swtpm-libs swtpm-dbgsym swtpm-dev swtpm-tools swtpm-tools-dbgsym
swtpm_CANONICAL := swtpm swtpm-libs swtpm-tools
swtpm_PKG_REFFILE := ./autogen.sh
swtpm_PKG_CMD_BOOTSTRAP := NOCONFIGURE=1 ./autogen.sh
swtpm_PKG_CMD_PACKAGE := dpkg-buildpackage -uc -us
swtpm_DEPENDS := swtpm-libs libtpms0
swtpm-dbgsym := swtpm libtpms0-dbgsym
swtpm-dev_DEPENDS := swtpm libtpms-dev
swtpm-tools_DEPENDS := swtpm
swtpm-tools-dbgsym_DEPENDS := swtpm-tools
swtpm_VERSION ?= 0.8.0
swtpm_RELEASE ?= ~dev1
swtpm_ARCH ?= amd64
swtpm_SUFFIX := $(swtpm_VERSION)$(swtpm_RELEASE)_$(swtpm_ARCH).deb
$(foreach p,$(swtpm_PKGS),$(eval $p_LOCAL_FILE := $p_$(swtpm_SUFFIX)))

$(eval $(call debian_build,\
	libtpms swtpm,\
	DEBBUILDER,\
	$(HCP_SRC)/ext/tpmware.Makefile))
