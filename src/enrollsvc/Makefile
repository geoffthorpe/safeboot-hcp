HCP_ENROLLSVC_SRC := $(TOP)/src/enrollsvc
HCP_ENROLLSVC_INSTALL_DEST := /hcp/enrollsvc

$(eval $(call builder_initialize,\
	enrollsvc,\
	$(HCP_ENROLLSVC_SRC),\
	$(HCP_ENROLLSVC_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	enrollsvc,\
	esvcscripts,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install -t $(HCP_ENROLLSVC_INSTALL_DEST) *.sh *.py,\
	))
$(eval $(call builder_codebase_simpledep,\
	enrollsvc,\
	esvcscripts))
$(eval $(call builder_add_codebase,\
	enrollsvc,\
	esvcgenprogs,\
	,\
	genprogs,\
	gencert-hxtool,\
	true,\
	true,\
	true,\
	install -D -t $(HCP_ENROLLSVC_INSTALL_DEST)/genprogs *,\
	))
$(eval $(call builder_codebase_simpledep,\
	enrollsvc,\
	esvcgenprogs))

$(eval $(call builder_finalize,enrollsvc))
