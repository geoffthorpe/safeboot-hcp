HCP_HCP_SRC := $(HCP_SRC)/hcp
HCP_HCP_PREFIX := /hcp

# We prepare most of our docker-run argument in advance, couple of reasons;
# - avoid very long lines
# - escape the required comma character (which GNU Make can't escape in any
#   context that expects comma-separated arguments)
$(eval MOUNTSRC := source=$(HCP_HCP_SRC)/install.Makefile)
$(eval MOUNTDST := destination=/hcp.Makefile)
$(eval comma := ,)
$(eval MOUNTARG := type=bind$(comma)$(MOUNTSRC)$(comma)$(MOUNTDST)$(comma)readonly)
hcp_CMD_INSTALL := LOCAL_PREFIX=$(HCP_HCP_PREFIX) make -f /hcp.Makefile install
$(eval $(call builder_add,\
	hcp,\
	$(HCP_HCP_SRC),\
	,\
	,\
	--mount $(MOUNTARG)))

$(eval $(call builder_simpledep,hcp))
