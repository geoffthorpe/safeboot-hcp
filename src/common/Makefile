HCP_COMMON_SRC := $(TOP)/src/common
HCP_COMMON_INSTALL_DEST := /hcp/common

$(eval $(call builder_initialize,\
	common,\
	$(HCP_COMMON_SRC),\
	$(HCP_COMMON_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	common,\
	common,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install *.sh *.py $(HCP_COMMON_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	common,\
	common))

$(eval $(call builder_finalize,common))
