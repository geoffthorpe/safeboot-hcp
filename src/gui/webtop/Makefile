HCP_GUIWEBTOP_SRC := $(HCP_GUI_SRC)/webtop
HCP_GUIWEBTOP_OUT := $(HCP_GUI_OUT)/webtop
HCP_GUIWEBTOP_DNAME := $(call HCP_IMAGE,guiwebtop)
HCP_GUIWEBTOP_DFILE := $(HCP_GUIWEBTOP_OUT)/Dockerfile
HCP_GUIWEBTOP_TFILE := $(HCP_GUIWEBTOP_OUT)/built

$(HCP_GUIWEBTOP_OUT): | $(HCP_GUI_OUT)
MDIRS += $(HCP_GUIWEBTOP_OUT)

guiwebtop: $(HCP_GUIWEBTOP_TFILE)
ALL += $(HCP_GUIWEBTOP_TFILE)

$(HCP_GUIWEBTOP_DFILE): | $(HCP_GUIWEBTOP_OUT)
$(HCP_GUIWEBTOP_DFILE): $(HCP_GUIWEBTOP_SRC)/Makefile
$(HCP_GUIWEBTOP_DFILE): $(HCP_GUIWEBTOP_SRC)/Dockerfile
$(HCP_GUIWEBTOP_DFILE):
	$Qecho "FROM $(HCP_GUIRDESKTOPWEB_DNAME)" > $@
	$Qcat $(HCP_GUIWEBTOP_SRC)/Dockerfile >> $@

$(HCP_GUIWEBTOP_OUT)/files-extracted: | $(HCP_GUIWEBTOP_OUT)
$(HCP_GUIWEBTOP_OUT)/files-extracted: $(HCP_GUIWEBTOP_SRC)/files.tar.gz
$(HCP_GUIWEBTOP_OUT)/files-extracted: 
	$Qcd $(HCP_GUIWEBTOP_OUT) && \
		rm -rf root/ && \
		tar zxf $(HCP_GUIWEBTOP_SRC)/files.tar.gz && \
		touch $@
$(HCP_GUIWEBTOP_TFILE): $(HCP_GUIWEBTOP_DFILE)
$(HCP_GUIWEBTOP_TFILE): $(HCP_GUIRDESKTOPWEB_TFILE)
$(HCP_GUIWEBTOP_TFILE): $(HCP_GUIWEBTOP_OUT)/files-extracted
$(HCP_GUIWEBTOP_TFILE):
	$Qecho "Building container image $(HCP_GUIWEBTOP_DNAME)"
	$Qdocker build -t $(HCP_GUIWEBTOP_DNAME) \
	               -f $(HCP_GUIWEBTOP_DFILE) \
		       --build-arg HCP_WEBTOP_PKGS="$(HCP_WEBTOP_PKGS)" \
		       --build-arg HCP_WEBTOP_CMD="$(HCP_WEBTOP_CMD)" \
	               $(HCP_GUIWEBTOP_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_GUIWEBTOP_TFILE),\
	$(HCP_GUIWEBTOP_DNAME),\
	guiwebtop,\
	clean_guiwebtop))

# Cleanup (note, we allow 'rm -rf' rather than 'rm' here, because files.tar.gz
# is extracted)
ifneq (,$(wildcard $(HCP_GUIWEBTOP_OUT)))
clean_guiwebtop: | preclean
	$Qrm -f $(HCP_GUIWEBTOP_DFILE) $(HCP_GUIWEBTOP_TFILE)
	$Qrm -rf $(HCP_GUIWEBTOP_OUT)
clean_guibuilder: clean_guiwebtop
endif
