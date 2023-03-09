HCP_APPS_OUT := $(HCP_OUT)/apps
HCP_APPS_SRC := $(HCP_SRC)/apps

$(HCP_APPS_OUT): | $(HCP_OUT)
MDIRS += $(HCP_APPS_OUT)

ifneq (,$(wildcard $(HCP_APPS_OUT)))
clean_apps:
	$Qrmdir $(HCP_APPS_OUT)
clean: clean_apps
endif

#################
# APPS_PRE_BASE #
#################

# We create this layer with the commonly-required upstream packages _before_
# creating layers with the possibly-locally-built upstream and
# HCP-specific packages.
apps_pre_base_pkgs := json-glib-tools libjson-perl libncurses5-dev \
	python3 python3-yaml python3-netifaces python3-psutil \
	python3-cryptography python3-openssl \
	python3-flask python3-requests uwsgi-plugin-python3 \
	nginx uuid-runtime \
	openssh-server gnutls-bin libglib2.0-0 openssl vde2
$(eval $(call pp_add_layer,\
	APPS_PRE_BASE,\
	BASE,\
	APPS,\
	$(apps_pre_base_pkgs),\
	$(HCP_SRC)/apps/base.Dockerfile,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))

# These are the possibly-locally-built upstream packages
apps_base_pkgs := swtpm-tools tpm2-tools heimdal safeboot

############
# Caboodle #
############

$(eval $(call pp_add_layer,\
	CABOODLE_BASE,\
	APPS_PRE_BASE,\
	APPS,\
	$(apps_base_pkgs),\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))
$(eval $(call pp_add_layer,\
	CABOODLE,\
	CABOODLE_BASE,\
	APPS,\
	hcp,\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))

###############
# UML version #
###############

ifdef HCP_APP_UML
uml_pre_base_pkgs := kmod isc-dhcp-client initramfs-tools
$(eval $(call pp_add_layer,\
	UML_PRE_BASE,\
	APPS_PRE_BASE,\
	APPS,\
	$(uml_pre_base_pkgs),\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))
$(eval $(call pp_add_layer,\
	UML_CABOODLE_BASE,\
	UML_PRE_BASE,\
	APPS,\
	$(apps_base_pkgs),\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))
$(eval $(call pp_add_layer,\
	UML_CABOODLE,\
	UML_CABOODLE_BASE,\
	APPS,\
	hcp,\
	$(HCP_UML_SRC)/imager.Dockerfile,\
	$(HCP_SRC)/apps/Makefile $(HCP_UML_BUILDER_TFILE),\
	,\
	$(HCP_UML_SRC)/init.sh $(HCP_UML_SRC)/hcp_mkext4.sh))

$(HCP_APPS_OUT)/uml_caboodle.tar: $(HCP_UML_CABOODLE_TFILE)
$(HCP_APPS_OUT)/uml_caboodle.tar: $(HCP_UML_SRC)/hcp_mkext4.sh
$(HCP_APPS_OUT)/uml_caboodle.tar:
	$Q$(HCP_UML_SRC)/hcp_mkext4.sh \
		dname2tar $(HCP_UML_CABOODLE_DNAME) $@
$(HCP_APPS_OUT)/uml_caboodle.ext4: $(HCP_APPS_OUT)/uml_caboodle.tar
$(HCP_APPS_OUT)/uml_caboodle.ext4: $(HCP_UML_RUN_TFILE)
$(HCP_APPS_OUT)/uml_caboodle.ext4: $(HCP_UML_IMAGER_PATH)
$(HCP_APPS_OUT)/uml_caboodle.ext4:
	$QBOOTSTRAP_IMG="$(HCP_UML_IMAGER_PATH)" \
		BOOTSTRAP_DNAME="$(HCP_UML_RUN_DNAME)" \
		$(HCP_UML_SRC)/hcp_mkext4.sh \
		tar2ext4 $(HCP_APPS_OUT)/uml_caboodle.tar $@ $(HCP_UML_EXT4_MB) unused
HCP_CABOODLE_UML_PATH := $(HCP_APPS_OUT)/uml_caboodle.ext4
ALL += $(HCP_CABOODLE_UML_PATH)
ifneq (,$(wildcard $(HCP_APPS_OUT)/uml_caboodle.tar $(HCP_APPS_OUT)/uml_caboodle.ext4))
clean_uml_caboodle_pieces:
	$Qrm -f $(HCP_APPS_OUT)/uml_caboodle.tar $(HCP_APPS_OUT)/uml_caboodle.ext4
clean_uml_caboodle: clean_uml_caboodle_pieces
endif

endif # HCP_APP_UML

################
# QEMU version #
################

ifdef HCP_APP_QEMU
qemu_pre_base_pkgs := $(uml_pre_base_pkgs)
# If UML is built too, these docker layers should cache-match
$(eval $(call pp_add_layer,\
	QEMU_PRE_BASE,\
	APPS_PRE_BASE,\
	APPS,\
	$(qemu_pre_base_pkgs) linux-image-amd64 systemd-sysv qemu-system-x86,\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))
$(eval $(call pp_add_layer,\
	QEMU_BASE,\
	QEMU_PRE_BASE,\
	APPS,\
	$(apps_base_pkgs),\
	,\
	$(HCP_SRC)/apps/Makefile,\
	,\
	))
$(eval $(call pp_add_layer,\
	QEMU,\
	QEMU_BASE,\
	APPS,\
	hcp,\
	$(HCP_APPS_SRC)/qemu_rootfs.Dockerfile,\
	$(HCP_SRC)/apps/Makefile $(HCP_UML_BUILDER_TFILE),\
	,\
	))

$(HCP_APPS_OUT)/qemu_caboodle.tar: $(HCP_QEMU_TFILE)
$(HCP_APPS_OUT)/qemu_caboodle.tar: $(HCP_UML_SRC)/hcp_mkext4.sh
$(HCP_APPS_OUT)/qemu_caboodle.tar:
	$Q$(HCP_UML_SRC)/hcp_mkext4.sh \
		dname2tar $(HCP_QEMU_DNAME) $@
HCP_QEMU_IMG := $(HCP_APPS_OUT)/qemu_caboodle_img
$(HCP_QEMU_IMG): | $(HCP_APPS_OUT)
MDIRS += $(HCP_QEMU_IMG)
$(HCP_QEMU_IMG)/disk: | $(HCP_QEMU_IMG)
$(HCP_QEMU_IMG)/disk: $(HCP_APPS_OUT)/qemu_caboodle.tar
$(HCP_QEMU_IMG)/disk: $(HCP_UML_RUN_TFILE)
$(HCP_QEMU_IMG)/disk: $(HCP_UML_IMAGER_PATH)
$(HCP_QEMU_IMG)/disk:
	$QBOOTSTRAP_IMG="$(HCP_UML_IMAGER_PATH)" \
		BOOTSTRAP_DNAME="$(HCP_UML_RUN_DNAME)" \
		$(HCP_UML_SRC)/hcp_mkext4.sh \
			tar2img $(HCP_APPS_OUT)/qemu_caboodle.tar \
				$(HCP_QEMU_IMG) $(HCP_QEMU_DISK_MB) unused
ALL += $(HCP_QEMU_IMG)/disk
ifneq (,$(wildcard $(HCP_APPS_OUT)/qemu_caboodle.tar $(HCP_QEMU_IMG)))
clean_qemu_caboodle_pieces:
	$Qrm -f $(HCP_APPS_OUT)/qemu_caboodle.tar
	$Qrm -f $(HCP_QEMU_IMG)/{disk,vmlinuz,initrd.img}
	$Qif test -d $(HCP_QEMU_IMG); then rmdir $(HCP_QEMU_IMG); fi
clean_qemu_caboodle: clean_qemu_caboodle_pieces
endif

endif # HCP_APP_QEMU
