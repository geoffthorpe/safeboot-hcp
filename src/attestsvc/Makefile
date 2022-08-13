HCP_ATTESTSVC_SRC := $(TOP)/src/attestsvc
HCP_ATTESTSVC_INSTALL_DEST := /hcp/attestsvc

$(eval $(call builder_initialize,\
	attestsvc,\
	$(HCP_ATTESTSVC_SRC),\
	$(HCP_ATTESTSVC_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	attestsvc,\
	asvcscripts,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install *.sh *.py $(HCP_ATTESTSVC_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	attestsvc,\
	asvcscripts))

$(eval $(call builder_finalize,attestsvc))
