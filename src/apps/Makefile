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
include $(HCP_APPS_SRC)/usecase/Makefile

# Produce container images
include $(HCP_APPS_SRC)/Makefile.images
$(eval $(call app_image,enrollsvc,common enrollsvc usecase,install safeboot))
$(eval $(call app_image,attestsvc,common attestsvc usecase,install safeboot))
$(eval $(call app_image,swtpmsvc,common swtpmsvc usecase,install safeboot))
$(eval $(call app_image,tools,common tools usecase,install safeboot))
$(eval $(call app_image,caboodle,common enrollsvc attestsvc swtpmsvc tools caboodle usecase,install safeboot))

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
