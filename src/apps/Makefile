HCP_APPS_OUT := $(HCP_OUT)/apps
HCP_APPS_SRC := $(HCP_SRC)/apps

$(HCP_APPS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_APPS_OUT)

# Include the app_image() subroutine
include $(HCP_APPS_SRC)/Makefile.sub

# Build a hcp_common image on top of base-platform that includes all
# our non-app code
$(eval $(call app_image,common,,safeboot tpmware heimdal xtra common))

# Build a hcp_caboodle image with everything
$(eval $(call app_image,caboodle,common,\
	caboodle enrollsvc attestsvc policysvc swtpmsvc tools kdcsvc))

# Only build service/tools-specific images if requested
ifdef HCP_APPS_GRANULAR
$(eval $(call app_image,tools,common,tools))
$(eval $(call app_image,enrollsvc,tools,enrollsvc swtpmsvc))
$(eval $(call app_image,attestsvc,common,attestsvc))
$(eval $(call app_image,policysvc,common,policysvc))
$(eval $(call app_image,swtpmsvc,common,swtpmsvc))
$(eval $(call app_image,kdcsvc,tools,kdcsvc))
else
$(eval $(call app_alias,tools,caboodle))
$(eval $(call app_alias,enrollsvc,caboodle))
$(eval $(call app_alias,attestsvc,caboodle))
$(eval $(call app_alias,policysvc,caboodle))
$(eval $(call app_alias,swtpmsvc,caboodle))
$(eval $(call app_alias,kdcsvc,caboodle))
endif

# Post-process now that all apps are registered
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
