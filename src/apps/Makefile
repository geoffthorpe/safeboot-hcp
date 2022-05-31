HCP_APPS_OUT := $(HCP_OUT)/apps
HCP_APPS_SRC := $(HCP_SRC)/apps

$(HCP_APPS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_APPS_OUT)

# Produce code tarballs
include $(HCP_APPS_SRC)/Makefile.code
include $(HCP_APPS_SRC)/common/Makefile
include $(HCP_APPS_SRC)/enrollsvc/Makefile
include $(HCP_APPS_SRC)/attestsvc/Makefile
include $(HCP_APPS_SRC)/swtpmsvc/Makefile
include $(HCP_APPS_SRC)/tools/Makefile
include $(HCP_APPS_SRC)/caboodle/Makefile

# Produce container images
include $(HCP_APPS_SRC)/Makefile.images
$(eval $(call app_image,enrollsvc,common enrollsvc,install safeboot))
$(eval $(call app_image,attestsvc,common attestsvc,install safeboot))
$(eval $(call app_image,swtpmsvc,common swtpmsvc,install safeboot))
$(eval $(call app_image,tools,common tools,install safeboot))
$(eval $(call app_image,caboodle,common enrollsvc attestsvc swtpmsvc kdc tools caboodle,install safeboot))

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
