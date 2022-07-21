HCP_APPS_OUT := $(HCP_OUT)/apps
HCP_APPS_SRC := $(HCP_SRC)/apps

$(HCP_APPS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_APPS_OUT)

# HCP_CODEBALLS is the list of codebases, <foo>, that get installed to
# /hcp/<foo> in container images. Their code is assumed to be in src/apps/<foo>,
# which must contain a Makefile. Those Makefiles are of the form;
#
# (0 or more subsets of files with corresponding chmod attributes)
#    $(eval $(call app_add,<foo>,shell-exec,755,run_*.sh))
#    $(eval $(call app_add,<foo>,shell-include,644,common.env))
#    $(eval $(call app_add,<foo>,utils,755,util_*.sh util_*.py))
# (0 or more finalizers to declare output tarballs)
#    $(eval $(call app_finalize,<foo>))
# (0 or more container images, producing "hcp_<fooapp>", that includes the
# named list of tarballs from HCP_CODEBALLS, plus 0 or more external tarballs,
# as required)
#    $(eval $(call app_image,<fooapp>,<foo1> <foo2>,<ext1> <ext2>))

HCP_CODEBALLS := common enrollsvc attestsvc swtpmsvc tools kdc policysvc caboodle

include $(HCP_APPS_SRC)/Makefile.code
include $(HCP_APPS_SRC)/Makefile.images

include $(foreach i,$(HCP_CODEBALLS),$(HCP_APPS_SRC)/$i/Makefile)

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
