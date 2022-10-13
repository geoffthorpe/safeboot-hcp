HCP_SSHSVC_SRC := $(TOP)/src/sshsvc
HCP_SSHSVC_INSTALL_DEST := /hcp/sshsvc

$(eval $(call builder_initialize,\
	sshsvc,\
	$(HCP_SSHSVC_SRC),\
	$(HCP_SSHSVC_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	sshsvc,\
	sshsvc,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install *.sh $(HCP_SSHSVC_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	sshsvc,\
	sshsvc))

$(eval $(call builder_finalize,sshsvc))
