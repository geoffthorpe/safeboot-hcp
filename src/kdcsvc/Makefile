HCP_KDCSVC_SRC := $(TOP)/src/kdcsvc
HCP_KDCSVC_INSTALL_DEST := /hcp/kdcsvc

$(eval $(call builder_initialize,\
	kdcsvc,\
	$(HCP_KDCSVC_SRC),\
	$(HCP_KDCSVC_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	kdcsvc,\
	kdcsvc,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install *.sh *.py $(HCP_KDCSVC_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	kdcsvc,\
	kdcsvc))

$(eval $(call builder_finalize,kdcsvc))
