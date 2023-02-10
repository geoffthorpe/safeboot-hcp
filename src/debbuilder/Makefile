HCP_DEBBUILDER_SRC := $(HCP_SRC)/debbuilder

$(eval $(call pp_add_layer,\
	DEBBUILDER,\
	BASE,\
	,\
	build-essential devscripts dpkg-dev,\
	,\
	$(HCP_DEBBUILDER_SRC)/Makefile,\
	,\
	))

ifdef HCP_LOCAL_SWTPM

include $(HCP_DEBBUILDER_SRC)/Makefile.libtpms
include $(HCP_DEBBUILDER_SRC)/Makefile.swtpm

endif
