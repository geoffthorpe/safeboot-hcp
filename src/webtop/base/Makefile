HCP_WEBTOPBASE_SRC := $(HCP_WEBTOP_SRC)/base
HCP_WEBTOPBASE_OUT := $(HCP_WEBTOP_OUT)/base
HCP_WEBTOPBASE_DNAME := $(call HCP_IMAGE,webtopbase)
HCP_WEBTOPBASE_DFILE := $(HCP_WEBTOPBASE_OUT)/Dockerfile
HCP_WEBTOPBASE_TFILE := $(HCP_WEBTOPBASE_OUT)/built

$(HCP_WEBTOPBASE_OUT): | $(HCP_WEBTOP_OUT)
MDIRS += $(HCP_WEBTOPBASE_OUT)

webtopbase: $(HCP_WEBTOPBASE_TFILE)
ALL += $(HCP_WEBTOPBASE_TFILE)

$(HCP_WEBTOPBASE_DFILE): | $(HCP_WEBTOPBASE_OUT)
$(HCP_WEBTOPBASE_DFILE): $(HCP_WEBTOPBASE_SRC)/Makefile
$(HCP_WEBTOPBASE_DFILE): $(HCP_WEBTOPBASE_SRC)/Dockerfile
$(HCP_WEBTOPBASE_DFILE):
	$Qecho "FROM $(HCP_BASE_DNAME)" > $@
	$Qcat $(HCP_WEBTOPBASE_SRC)/Dockerfile >> $@


$(HCP_WEBTOPBASE_OUT)/deb_contrib_nonfree_ify.sh: | $(HCP_WEBTOPBASE_OUT)
$(HCP_WEBTOPBASE_OUT)/deb_contrib_nonfree_ify.sh: $(HCP_WEBTOPBASE_SRC)/deb_contrib_nonfree_ify.sh
$(HCP_WEBTOPBASE_OUT)/deb_contrib_nonfree_ify.sh:
	$Qcp $< $@

$(HCP_WEBTOPBASE_OUT)/files.tar.gz: | $(HCP_WEBTOPBASE_OUT)
$(HCP_WEBTOPBASE_OUT)/files.tar.gz: $(HCP_WEBTOPBASE_SRC)/files.tar.gz
$(HCP_WEBTOPBASE_OUT)/files.tar.gz:
	$Qcp $< $@

$(HCP_WEBTOPBASE_TFILE): $(HCP_WEBTOPBASE_DFILE)
$(HCP_WEBTOPBASE_TFILE): $(HCP_BASE_TFILE)
$(HCP_WEBTOPBASE_TFILE): $(HCP_WEBTOPBASE_OUT)/deb_contrib_nonfree_ify.sh
$(HCP_WEBTOPBASE_TFILE): $(HCP_WEBTOPBASE_OUT)/files.tar.gz
$(HCP_WEBTOPBASE_TFILE):
	$Qecho "Building container image $(HCP_WEBTOPBASE_DNAME)"
	$Qdocker build -t $(HCP_WEBTOPBASE_DNAME) \
	               -f $(HCP_WEBTOPBASE_DFILE) \
	               $(HCP_WEBTOPBASE_OUT)
	$Qtouch $@
$(eval $(call pp_rule_docker_image_rm,\
	$(HCP_WEBTOPBASE_TFILE),\
	$(HCP_WEBTOPBASE_DNAME),\
	webtopbase,\
	clean_webtopbase))

# Cleanup
ifneq (,$(wildcard $(HCP_WEBTOPBASE_OUT)))
clean_webtopbase: | preclean
	$Qrm -f $(HCP_WEBTOPBASE_DFILE)
	$Qrm -rf $(HCP_WEBTOPBASE_OUT)
clean_webtop: clean_webtopbase
clean_base: clean_webtopbase
endif
