HCP_GUIBUILDER_SRC := $(HCP_GUI_SRC)/builder
HCP_GUIBUILDER_OUT := $(HCP_GUI_OUT)/builder
HCP_GUIBUILDER_DNAME := $(call HCP_IMAGE,guibuilder)
HCP_GUIBUILDER_DFILE := $(HCP_GUIBUILDER_OUT)/Dockerfile
HCP_GUIBUILDER_TFILE := $(HCP_GUIBUILDER_OUT)/built

$(HCP_GUIBUILDER_OUT): | $(HCP_GUI_OUT)
MDIRS += $(HCP_GUIBUILDER_OUT)

# A wrapper target to build the "guibuilder" image
guibuilder: $(HCP_GUIBUILDER_TFILE)
ALL += $(HCP_GUIBUILDER_TFILE)

$(HCP_GUIBUILDER_DFILE): | $(HCP_GUIBUILDER_OUT)
$(HCP_GUIBUILDER_DFILE): $(HCP_GUIBUILDER_SRC)/Makefile
$(HCP_GUIBUILDER_DFILE): $(HCP_GUIBUILDER_SRC)/Dockerfile
$(HCP_GUIBUILDER_DFILE):
	$Qecho "FROM $(HCP_GUIBASE_DNAME)" > $@
	$Qcat $(HCP_GUIBUILDER_SRC)/Dockerfile >> $@

# Have GUIBUILDER use the same deb_src_ify.sh as BUILDER
$(HCP_GUIBUILDER_OUT)/deb_src_ify.sh: | $(HCP_GUIBUILDER_OUT)
$(HCP_GUIBUILDER_OUT)/deb_src_ify.sh: $(HCP_BUILDER_SRC)/deb_src_ify.sh
$(HCP_GUIBUILDER_OUT)/deb_src_ify.sh:
	$Qcp $< $@

$(HCP_GUIBUILDER_TFILE): $(HCP_GUIBUILDER_DFILE)
$(HCP_GUIBUILDER_TFILE): $(HCP_GUIBUILDER_OUT)/deb_src_ify.sh
$(HCP_GUIBUILDER_TFILE): $(HCP_GUIBASE_TFILE)
$(HCP_GUIBUILDER_TFILE):
	$Qecho "Building container image $(HCP_GUIBUILDER_DNAME)"
	$Qdocker build -t $(HCP_GUIBUILDER_DNAME) \
	               -f $(HCP_GUIBUILDER_DFILE) \
	               $(HCP_GUIBUILDER_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_GUIBUILDER_TFILE),\
	$(HCP_GUIBUILDER_DNAME),\
	guibuilder,\
	clean_guibuilder))

# Cleanup
ifneq (,$(wildcard $(HCP_GUIBUILDER_OUT)))
clean_guibuilder: | preclean
	$Qrm -f $(HCP_GUIBUILDER_DFILE) $(HCP_GUIBUILDER_OUT)/deb_src_ify.sh
	$Qrmdir $(HCP_GUIBUILDER_OUT)
clean_guibase: clean_guibuilder
endif
