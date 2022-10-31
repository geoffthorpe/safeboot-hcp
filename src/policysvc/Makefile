HCP_POLICYSVC_SRC := $(TOP)/src/policysvc
HCP_POLICYSVC_INSTALL_DEST := /hcp/policysvc

$(eval $(call builder_initialize,\
	policysvc,\
	$(HCP_POLICYSVC_SRC),\
	$(HCP_POLICYSVC_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	policysvc,\
	policysvc,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install *.py $(HCP_POLICYSVC_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	policysvc,\
	policysvc))

$(eval $(call builder_finalize,policysvc))
