HCP_SAFEBOOT_SRC := $(TOP)/ext-safeboot
HCP_SAFEBOOT_PREFIX := /install-safeboot

# We prepare most of our docker-run argument in advance, couple of reasons;
# - avoid very long lines
# - escape the required comma character (which GNU Make can't escape in any
#   context that expects comma-separated arguments)
$(eval MOUNTSRC := source=$(HCP_SRC)/ext/safeboot-install.Makefile)
$(eval MOUNTDST := destination=/hcp.Makefile)
$(eval comma := ,)
$(eval MOUNTARG := type=bind$(comma)$(MOUNTSRC)$(comma)$(MOUNTDST)$(comma)readonly)
safeboot_CMD_INSTALL := LOCAL_PREFIX=$(HCP_SAFEBOOT_PREFIX) make -f /hcp.Makefile install
$(eval $(call builder_add,\
	safeboot,\
	$(HCP_SAFEBOOT_SRC),\
	,\
	,\
	--mount $(MOUNTARG)))

$(eval $(call builder_simpledep,safeboot))
