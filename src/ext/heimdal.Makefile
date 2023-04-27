HCP_HEIMDAL_SRC := $(TOP)/ext-heimdal
HCP_HEIMDAL_PREFIX := /usr

# Only compile-in heimdal if we're not using upstream packages
ifdef HCP_LOCAL_HEIMDAL

heimdal_CMD_BOOTSTRAP := ./autogen.sh
heimdal_CMD_CONFIGURE := MAKEINFO=true ./configure --disable-texinfo --prefix=$(HCP_HEIMDAL_PREFIX)
heimdal_CMD_COMPILE := MAKEINFO=true make $(HCP_BUILDER_MAKE_PARALLEL)
heimdal_CMD_INSTALL := MAKEINFO=true make $(HCP_BUILDER_MAKE_PARALLEL) install
$(eval $(call builder_add,\
	heimdal,\
	$(HCP_HEIMDAL_SRC),\
	,\
	,\
	))

$(eval $(call builder_simpledep,heimdal))

endif # HCP_LOCAL_HEIMDAL
