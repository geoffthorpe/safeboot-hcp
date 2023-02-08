HCP_APPS_OUT := $(HCP_OUT)/apps
HCP_APPS_SRC := $(HCP_SRC)/apps

$(HCP_APPS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_APPS_OUT)

# Prepare the HCP_APPS_BASE_DNAME, to include locally-(debbuilder)-built packages.
include $(HCP_APPS_SRC)/base/Makefile

# Include the app_image() subroutine
include $(HCP_APPS_SRC)/Makefile.sub

# hcp_precommon: base-platform plus all non-app-specific code (the launcher,
# fqdn-updater, purger, etc).
# hcp_common: this is hcp_precommon plus the baking-in of the launcher as the
# ENTRYPOINT. Think of this as the base class for all HCP apps.
$(eval $(call app_image,precommon,SYM:APPS_BASE,safeboot tpmware heimdal,,))
$(eval $(call app_image,common,precommon,,[\"/hcp/common/launcher.py\"],))

# hcp_caboodle: at the other extreme, this contains everything. It's an image
# that can run any of the HCP apps/purposes, because it contains the code for
# all of it.
$(eval $(call app_image,caboodle,common,caboodle,,))

# Post-process now that all apps are registered
$(eval $(call app_image_post,precommon))
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
