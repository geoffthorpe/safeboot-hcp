HCP_SWTPMSVC_SRC := $(TOP)/src/swtpmsvc
HCP_SWTPMSVC_INSTALL_DEST := /hcp/swtpmsvc

$(eval $(call builder_initialize,\
	swtpmsvc,\
	$(HCP_SWTPMSVC_SRC),\
	$(HCP_SWTPMSVC_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	swtpmsvc,\
	swtpmsvc,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install *.sh $(HCP_SWTPMSVC_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	swtpmsvc,\
	swtpmsvc))

$(eval $(call builder_finalize,swtpmsvc))
