HCP_GUIRDESKTOP_SRC := $(HCP_GUI_SRC)/rdesktop
HCP_GUIRDESKTOP_OUT := $(HCP_GUI_OUT)/rdesktop
HCP_GUIRDESKTOPBUILD_DNAME := $(call HCP_IMAGE,guirdesktop-build)
HCP_GUIRDESKTOPBUILD_DFILE := $(HCP_GUIRDESKTOP_OUT)/Dockerfile.build
HCP_GUIRDESKTOPBUILD_TFILE := $(HCP_GUIRDESKTOP_OUT)/built.build
HCP_GUIRDESKTOP_DNAME := $(call HCP_IMAGE,guirdesktop)
HCP_GUIRDESKTOP_DFILE := $(HCP_GUIRDESKTOP_OUT)/Dockerfile
HCP_GUIRDESKTOP_TFILE := $(HCP_GUIRDESKTOP_OUT)/built

$(HCP_GUIRDESKTOP_OUT): | $(HCP_GUI_OUT)
MDIRS += $(HCP_GUIRDESKTOP_OUT)

# "guirdesktop" is the intended result. "guirdesktop-build" is the
# guirdesktop-specific derivation of "guibuilder", which builds the stuff that
# guirdesktop depends on.
guirdesktop-build: $(HCP_GUIRDESKTOPBUILD_TFILE)
guirdesktop: $(HCP_GUIRDESKTOP_TFILE)
ALL += $(HCP_GUIRDESKTOPBUILD_TFILE) $(HCP_GUIRDESKTOP_TFILE)

$(HCP_GUIRDESKTOPBUILD_DFILE): | $(HCP_GUIRDESKTOP_OUT)
$(HCP_GUIRDESKTOPBUILD_DFILE): $(HCP_GUIRDESKTOP_SRC)/Makefile
$(HCP_GUIRDESKTOPBUILD_DFILE): $(HCP_GUIRDESKTOP_SRC)/Dockerfile.build
$(HCP_GUIRDESKTOPBUILD_DFILE):
	$Qecho "FROM $(HCP_GUIBUILDER_DNAME)" > $@
	$Qcat $(HCP_GUIRDESKTOP_SRC)/Dockerfile.build >> $@

$(HCP_GUIRDESKTOP_DFILE): | $(HCP_GUIRDESKTOP_OUT)
$(HCP_GUIRDESKTOP_DFILE): $(HCP_GUIRDESKTOP_SRC)/Makefile
$(HCP_GUIRDESKTOP_DFILE): $(HCP_GUIRDESKTOP_SRC)/Dockerfile
$(HCP_GUIRDESKTOP_DFILE):
	$Qecho "FROM $(HCP_GUIBASE_DNAME)" > $@
	$Qcat $(HCP_GUIRDESKTOP_SRC)/Dockerfile | \
		sed -e "s/%%BUILDER_DNAME%%/$(HCP_GUIRDESKTOPBUILD_DNAME)/" >> $@

$(HCP_GUIRDESKTOPBUILD_TFILE): $(HCP_GUIRDESKTOPBUILD_DFILE)
$(HCP_GUIRDESKTOPBUILD_TFILE): $(HCP_GUIBUILDER_TFILE)
$(HCP_GUIRDESKTOPBUILD_TFILE):
	$Qecho "Building container image $(HCP_GUIRDESKTOPBUILD_DNAME)"
	$Qdocker build -t $(HCP_GUIRDESKTOPBUILD_DNAME) \
	               -f $(HCP_GUIRDESKTOPBUILD_DFILE) \
	               $(HCP_GUIRDESKTOP_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_GUIRDESKTOPBUILD_TFILE),\
	$(HCP_GUIRDESKTOPBUILD_DNAME),\
	guirdesktop-build,\
	clean_guirdesktop))

$(HCP_GUIRDESKTOP_OUT)/files-extracted: | $(HCP_GUIRDESKTOP_OUT)
$(HCP_GUIRDESKTOP_OUT)/files-extracted: $(HCP_GUIRDESKTOP_SRC)/files.tar.gz
$(HCP_GUIRDESKTOP_OUT)/files-extracted: 
	$Qcd $(HCP_GUIRDESKTOP_OUT) && \
		rm -rf root/ && \
		tar zxf $(HCP_GUIRDESKTOP_SRC)/files.tar.gz && \
		touch $@

$(HCP_GUIRDESKTOP_TFILE): $(HCP_GUIRDESKTOP_DFILE)
$(HCP_GUIRDESKTOP_TFILE): $(HCP_GUIBASE_TFILE)
$(HCP_GUIRDESKTOP_TFILE): $(HCP_GUIRDESKTOPBUILD_TFILE)
$(HCP_GUIRDESKTOP_TFILE): $(HCP_GUIRDESKTOP_OUT)/files-extracted
$(HCP_GUIRDESKTOP_TFILE):
	$Qecho "Building container image $(HCP_GUIRDESKTOP_DNAME)"
	$Qdocker build -t $(HCP_GUIRDESKTOP_DNAME) \
	               -f $(HCP_GUIRDESKTOP_DFILE) \
	               $(HCP_GUIRDESKTOP_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_GUIRDESKTOP_TFILE),\
	$(HCP_GUIRDESKTOP_DNAME),\
	guirdesktop,\
	clean_guirdesktop))

# Cleanup
ifneq (,$(wildcard $(HCP_GUIRDESKTOP_OUT)))
clean_guirdesktop: | preclean
	$Qrm -f $(HCP_GUIRDESKTOP_DFILE)
	$Qrm -f $(HCP_GUIRDESKTOPBUILD_DFILE)
	$Qrm -rf $(HCP_GUIRDESKTOP_OUT)
clean_guibuilder: clean_guirdesktop
endif
