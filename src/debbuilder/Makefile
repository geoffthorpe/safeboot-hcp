HCP_DEBBUILDER_SRC := $(HCP_SRC)/debbuilder

$(eval $(call pp_add_layer,\
	DEBBUILDER,\
	BASE,\
	,\
	build-essential devscripts dpkg-dev,\
	,\
	$(HCP_SRC)/debbuilder/libtpms/Makefile,\
	))
