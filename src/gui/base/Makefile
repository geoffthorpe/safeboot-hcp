HCP_GUIBASE_SRC := $(HCP_GUI_SRC)/base
HCP_GUIBASE_OUT := $(HCP_GUI_OUT)/base
HCP_GUIBASE_DNAME := $(call HCP_IMAGE,guibase)
HCP_GUIBASE_DFILE := $(HCP_GUIBASE_OUT)/Dockerfile
HCP_GUIBASE_TFILE := $(HCP_GUIBASE_OUT)/built

$(HCP_GUIBASE_OUT): | $(HCP_GUI_OUT)
MDIRS += $(HCP_GUIBASE_OUT)

guibase: $(HCP_GUIBASE_TFILE)
ALL += $(HCP_GUIBASE_TFILE)

$(HCP_GUIBASE_DFILE): | $(HCP_GUIBASE_OUT)
$(HCP_GUIBASE_DFILE): $(HCP_GUIBASE_SRC)/Makefile
$(HCP_GUIBASE_DFILE): $(HCP_GUIBASE_SRC)/Dockerfile
$(HCP_GUIBASE_DFILE):
	$Qecho "FROM $(HCP_BASE_DNAME)" > $@
	$Qcat $(HCP_GUIBASE_SRC)/Dockerfile >> $@

$(HCP_GUIBASE_OUT)/deb_contrib_nonfree_ify.sh: | $(HCP_GUIBASE_OUT)
$(HCP_GUIBASE_OUT)/deb_contrib_nonfree_ify.sh: $(HCP_GUIBASE_SRC)/deb_contrib_nonfree_ify.sh
$(HCP_GUIBASE_OUT)/deb_contrib_nonfree_ify.sh:
	$Qcp $< $@

$(HCP_GUIBASE_OUT)/files-extracted: | $(HCP_GUIBASE_OUT)
$(HCP_GUIBASE_OUT)/files-extracted: $(HCP_GUIBASE_SRC)/files.tar.gz
$(HCP_GUIBASE_OUT)/files-extracted: 
	$Qcd $(HCP_GUIBASE_OUT) && \
		rm -rf root/ && \
		tar zxf $(HCP_GUIBASE_SRC)/files.tar.gz && \
		touch $@

$(HCP_GUIBASE_TFILE): $(HCP_GUIBASE_DFILE)
$(HCP_GUIBASE_TFILE): $(HCP_BASE_TFILE)
$(HCP_GUIBASE_TFILE): $(HCP_GUIBASE_OUT)/deb_contrib_nonfree_ify.sh
$(HCP_GUIBASE_TFILE): $(HCP_GUIBASE_OUT)/files-extracted
$(HCP_GUIBASE_TFILE):
	$Qecho "Building container image $(HCP_GUIBASE_DNAME)"
	$Qdocker build -t $(HCP_GUIBASE_DNAME) \
	               -f $(HCP_GUIBASE_DFILE) \
	               $(HCP_GUIBASE_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_GUIBASE_TFILE),\
	$(HCP_GUIBASE_DNAME),\
	guibase,\
	clean_guibase))

# Cleanup
ifneq (,$(wildcard $(HCP_GUIBASE_OUT)))
clean_guibase: | preclean
	$Qrm -f $(HCP_GUIBASE_DFILE)
	$Qrm -rf $(HCP_GUIBASE_OUT)
clean_gui: clean_guibase
clean_base: clean_guibase
endif
