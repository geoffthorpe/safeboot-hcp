HCP_CABOODLE_SRC := $(TOP)/src/caboodle
HCP_CABOODLE_INSTALL_DEST := /hcp/caboodle

$(eval $(call builder_initialize,\
	caboodle,\
	$(HCP_CABOODLE_SRC),\
	$(HCP_CABOODLE_INSTALL_DEST),,))

$(eval $(call builder_add_codebase,\
	caboodle,\
	caboodle,\
	,\
	.,\
	Makefile,\
	true,\
	true,\
	true,\
	install *.sh $(HCP_CABOODLE_INSTALL_DEST),\
	))
$(eval $(call builder_codebase_simpledep,\
	caboodle,\
	caboodle))

$(eval $(call builder_finalize,caboodle))
