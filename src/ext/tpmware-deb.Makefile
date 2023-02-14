###############################################
# PACKAGING WITH "DEBBUILDER": swtpm, libtpms #
###############################################

libtpms_PKG_SRC := $(TOP)/ext-tpmware/libtpms
libtpms_PKG_CMD_BOOTSTRAP := NOCONFIGURE=1 ./autogen.sh
libtpms_VERSION ?= 0.10.0
libtpms_RELEASE ?= ~dev1
libtpms_ARCH ?= amd64
libtpms_PKG_SUFFIX := _$(libtpms_VERSION)$(libtpms_RELEASE)_$(libtpms_ARCH).deb
$(eval $(call debian_build,libtpms,DEBBUILDER,\
		$(HCP_SRC)/ext/tpmware.Makefile))

swtpm_PKG_SRC := $(TOP)/ext-tpmware/swtpm
swtpm_PKG_CMD_BOOTSTRAP := NOCONFIGURE=1 ./autogen.sh
swtpm_VERSION ?= 0.8.0
swtpm_RELEASE ?= ~dev1
swtpm_ARCH ?= amd64
swtpm_PKG_SUFFIX := _$(swtpm_VERSION)$(swtpm_RELEASE)_$(swtpm_ARCH).deb
$(eval $(call debian_build,swtpm,DEBBUILDER,\
		$(HCP_SRC)/ext/tpmware.Makefile))
