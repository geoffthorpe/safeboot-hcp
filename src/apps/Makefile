HCP_APPS_OUT := $(HCP_OUT)/apps
HCP_APPS_SRC := $(HCP_SRC)/apps

$(HCP_APPS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_APPS_OUT)

# Include the app_image() subroutine
include $(HCP_APPS_SRC)/Makefile.sub

# hcp_precommon: base-platform plus all non-app-specific code (the launcher,
# fqdn-updater, purger, etc).
# hcp_common: this is hcp_precommon plus the baking-in of the launcher as the
# ENTRYPOINT. Think of this as the base class for all HCP apps.
$(eval $(call app_image,precommon,,safeboot tpmware heimdal xtra common,,))
$(eval $(call app_image,common,precommon,,[\"/hcp/common/launcher.py\"],))

# hcp_caboodle: at the other extreme, this contains everything. It's an image
# that can run any of the HCP apps/purposes, because it contains the code for
# all of it. If USE_GUITOP is defined, we will also derive caboodle from the
# 'webtop' image.
ifdef HCP_USE_WEBTOP
$(eval $(call app_image,caboodle,SYM:WEBTOPWEBTOP,\
	safeboot tpmware heimdal xtra common \
	caboodle enrollsvc attestsvc policysvc swtpmsvc kdcsvc sshsvc tools,\
	[\"/hcp/common/launcher.py\"],))
else
$(eval $(call app_image,caboodle,common,\
	caboodle enrollsvc attestsvc policysvc swtpmsvc kdcsvc sshsvc tools,,))
endif

ifdef HCP_APPS_GRANULAR
# Only build service/tools-specific images if requested. This is mostly a way
# to create purpose-specific images and tag them as such - the leaving out of
# other app code isn't really to save space (the difference is like a
# rounding-error) nor for any serious reduction in attack surface, but it does
# push the build system a bit harder, and testing with these images helps to
# check that the apps don't have any accidental interdepencies.
#
# hcp_common (no default command, has only the launcher and some libs)
#   |
#   +--> hcp_tools (no default command, has multiple choices)
#   |      |
#   |      +--> hcp_enrollsvc (no default command, as there are two choices)
#   |      |
#   |      +--> hcp_attestsvc (no default command, as there are two choices)
#   |      |
#   |      +--> hcp_swtpmsvc (default command)
#   |      |
#   |      +--> hcp_kdcsvc (default command)
#   |      |
#   |      +--> hcp_sshsvc (default command)
#   |
#   +--> hcp_policysvc (default command)
$(eval $(call app_image,tools,common,tools,,))
$(eval $(call app_image,enrollsvc,tools,enrollsvc swtpmsvc,,))
$(eval $(call app_image,attestsvc,tools,attestsvc,,))
$(eval $(call app_image,policysvc,common,policysvc,,))
$(eval $(call app_image,swtpmsvc,tools,swtpmsvc,,))
$(eval $(call app_image,kdcsvc,tools,kdcsvc,,))
$(eval $(call app_image,sshsvc,tools,sshsvc,,))
else
# Otherwise, use the 'hcp_caboodle' image for any and all purposes.
$(eval $(call app_alias,tools,caboodle))
$(eval $(call app_alias,enrollsvc,caboodle))
$(eval $(call app_alias,attestsvc,caboodle))
$(eval $(call app_alias,policysvc,caboodle))
$(eval $(call app_alias,swtpmsvc,caboodle))
$(eval $(call app_alias,kdcsvc,caboodle))
$(eval $(call app_alias,sshsvc,caboodle))
endif

# Post-process now that all apps are registered
APP_IMAGE_POST_BOTTOMTURTLE := precommon
ifdef HCP_USE_WEBTOP
APP_IMAGE_POST_BOTTOMTURTLE += WEBTOPWEBTOP
endif
$(eval $(call app_image_post,$(APP_IMAGE_POST_BOTTOMTURTLE)))
$(eval APPS_NAMES := $(strip $(APPS_NAMES)))
APPS := $(foreach i,$(APPS_NAMES),$(HCP_$i_TFILE))
ALL += $(APPS)

###########
# Wrapper #
###########

apps: $(APPS)

# Global cleanup
ifneq (,$(wildcard $(HCP_APPS_OUT)))
clean_apps:
	$Qrmdir $(HCP_APPS_OUT)
clean: clean_apps
endif
