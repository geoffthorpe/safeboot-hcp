HCP_WEBTOPWEBTOP_SRC := $(HCP_WEBTOP_SRC)/webtop
HCP_WEBTOPWEBTOP_OUT := $(HCP_WEBTOP_OUT)/webtop
HCP_WEBTOPWEBTOP_DNAME := $(call HCP_IMAGE,webtopwebtop)
HCP_WEBTOPWEBTOP_DFILE := $(HCP_WEBTOPWEBTOP_OUT)/Dockerfile
HCP_WEBTOPWEBTOP_TFILE := $(HCP_WEBTOPWEBTOP_OUT)/built

$(HCP_WEBTOPWEBTOP_OUT): | $(HCP_WEBTOP_OUT)
MDIRS += $(HCP_WEBTOPWEBTOP_OUT)

webtopwebtop: $(HCP_WEBTOPWEBTOP_TFILE)
ALL += $(HCP_WEBTOPWEBTOP_TFILE)

$(HCP_WEBTOPWEBTOP_DFILE): | $(HCP_WEBTOPWEBTOP_OUT)
$(HCP_WEBTOPWEBTOP_DFILE): $(HCP_WEBTOPWEBTOP_SRC)/Makefile
$(HCP_WEBTOPWEBTOP_DFILE): $(HCP_WEBTOPWEBTOP_SRC)/Dockerfile
$(HCP_WEBTOPWEBTOP_DFILE):
	$Qecho "FROM $(HCP_WEBTOPRDESKTOPWEB_DNAME)" > $@
	$Qcat $(HCP_WEBTOPWEBTOP_SRC)/Dockerfile >> $@

$(HCP_WEBTOPWEBTOP_OUT)/files.tar.gz: | $(HCP_WEBTOPWEBTOP_OUT)
$(HCP_WEBTOPWEBTOP_OUT)/files.tar.gz: $(HCP_WEBTOPWEBTOP_SRC)/files.tar.gz
$(HCP_WEBTOPWEBTOP_OUT)/files.tar.gz:
	$Qcp $< $@

$(HCP_WEBTOPWEBTOP_TFILE): $(HCP_WEBTOPWEBTOP_DFILE)
$(HCP_WEBTOPWEBTOP_TFILE): $(HCP_WEBTOPRDESKTOPWEB_TFILE)
$(HCP_WEBTOPWEBTOP_TFILE): $(HCP_WEBTOPWEBTOP_OUT)/files.tar.gz
$(HCP_WEBTOPWEBTOP_TFILE):
	$Qecho "Building container image $(HCP_WEBTOPWEBTOP_DNAME)"
	$Qdocker build -t $(HCP_WEBTOPWEBTOP_DNAME) \
	               -f $(HCP_WEBTOPWEBTOP_DFILE) \
		       --build-arg HCP_WEBTOP_PKGS="$(HCP_WEBTOP_PKGS)" \
		       --build-arg HCP_WEBTOP_CMD="$(HCP_WEBTOP_CMD)" \
	               $(HCP_WEBTOPWEBTOP_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_WEBTOPWEBTOP_TFILE),\
	$(HCP_WEBTOPWEBTOP_DNAME),\
	webtopwebtop,\
	clean_webtopwebtop))

# Cleanup (note, we allow 'rm -rf' rather than 'rm' here, because files.tar.gz
# is extracted)
ifneq (,$(wildcard $(HCP_WEBTOPWEBTOP_OUT)))
clean_webtopwebtop: | preclean
	$Qrm -f $(HCP_WEBTOPWEBTOP_DFILE) $(HCP_WEBTOPWEBTOP_TFILE)
	$Qrm -rf $(HCP_WEBTOPWEBTOP_OUT)
clean_webtopbuilder: clean_webtopwebtop
endif
