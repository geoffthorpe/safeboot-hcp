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
	openssh-server gnutls-bin libglib2.0-0 openssl socat
APPS_PRE_BASE_FILES := $(HCP_SRC)/apps/ssh_config
APPS_PRE_BASE_DEPFILES := $(HCP_SRC)/apps/Makefile
APPS_PRE_BASE_DSTUB := $(HCP_SRC)/apps/base.Dockerfile
$(eval $(call pp_add_layer,\
	APPS_PRE_BASE,\
	BASE,\
	APPS,\
	$(apps_pre_base_pkgs)))

# These are the possibly-locally-built upstream packages
apps_base_pkgs := swtpm-tools tpm2-tools heimdal safeboot vdeplug_slirp vde2

# And our in-tree source comes last. And if HCP_MOUNT is defined, then we don't
# install 'hcp' into container images at all.
ifdef HCP_MOUNT
hcp_pkg :=
else
hcp_pkg := hcp
endif

############
# Caboodle #
############

CABOODLE_BASE_DEPFILES := $(HCP_SRC)/apps/Makefile
$(eval $(call pp_add_layer,\
	CABOODLE_BASE,\
	APPS_PRE_BASE,\
	APPS,\
	$(apps_base_pkgs)))
CABOODLE_DEPFILES := $(HCP_SRC)/apps/Makefile
$(eval $(call pp_add_layer,\
	CABOODLE,\
	CABOODLE_BASE,\
	APPS,\
	$(hcp_pkg)))
ALL += $(HCP_CABOODLE_TFILE)
HCP_DOCKER_IMGS += caboodle

###############
# UML version #
###############

# For now, we arrange for the UML_CABOODLE container image to be usable, (a)
# for the container that launches the UML VM (the "runner"), and (b) the basis
# for a bootable image to run workloads.
ifdef HCP_APP_UML
uml_base_pkgs := kmod isc-dhcp-client initramfs-tools uml-kbuild
UML_CABOODLE_BASE := $(HCP_SRC)/apps/Makefile
$(eval $(call pp_add_layer,\
	UML_CABOODLE_BASE,\
	CABOODLE_BASE,\
	APPS,\
	$(uml_base_pkgs)))
UML_CABOODLE_FILES := $(HCP_UML_SRC)/uml_init.py
UML_CABOODLE_DEPFILES := $(HCP_SRC)/apps/Makefile
UML_CABOODLE_DSTUB := $(HCP_UML_SRC)/uml_init.Dockerfile
$(eval $(call pp_add_layer,\
	UML_CABOODLE,\
	UML_CABOODLE_BASE,\
	APPS,\
	$(hcp_pkg)))

$(HCP_APPS_OUT)/uml_caboodle.tar: $(HCP_UML_CABOODLE_TFILE)
$(HCP_APPS_OUT)/uml_caboodle.tar: $(HCP_UML_SRC)/hcp_mkext4.sh
$(HCP_APPS_OUT)/uml_caboodle.tar: $(HCP_BOOTSTRAP_CMD_DEPS)
$(HCP_APPS_OUT)/uml_caboodle.tar:
	$Q$(HCP_BOOTSTRAP_CMD) dname2tar \
		$(HCP_UML_CABOODLE_DNAME) $@
HCP_CABOODLE_UML_PATH := $(HCP_APPS_OUT)/uml_caboodle.ext4
$(HCP_CABOODLE_UML_PATH): $(HCP_APPS_OUT)/uml_caboodle.tar
$(HCP_CABOODLE_UML_PATH):
	$Q$(HCP_BOOTSTRAP_CMD) tar2ext4 \
		$(HCP_APPS_OUT)/uml_caboodle.tar $@ $(HCP_UML_EXT4_MB) unused
ALL += $(HCP_CABOODLE_UML_PATH)
HCP_DOCKER_IMGS += uml_caboodle
ifneq (,$(wildcard $(HCP_APPS_OUT)/uml_caboodle.tar $(HCP_CABOODLE_UML_PATH)))
clean_uml_caboodle_pieces:
	$Qrm -f $(HCP_APPS_OUT)/uml_caboodle.tar $(HCP_CABOODLE_UML_PATH)
clean_uml_caboodle: clean_uml_caboodle_pieces
endif

endif # HCP_APP_UML

################
# QEMU version #
################

ifdef HCP_APP_QEMU
qemu_base_pkgs := $(uml_base_pkgs)
qemu_base_pkgs += linux-image-amd64 systemd-sysv qemu-system-x86
qemu_base_pkgs += qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
QEMU_CABOODLE_BASE_DEPFILES := $(HCP_SRC)/apps/Makefile
$(eval $(call pp_add_layer,\
	QEMU_CABOODLE_BASE,\
	CABOODLE_BASE,\
	APPS,\
	$(qemu_base_pkgs)))
QEMU_CABOODLE_FILES := $(HCP_UML_SRC)/qemu_init.py \
		$(HCP_UML_SRC)/10-vde.link \
		$(HCP_UML_SRC)/25-vde.network \
		$(HCP_UML_SRC)/hcp_systemd.service
QEMU_CABOODLE_DEPFILES := $(HCP_SRC)/apps/Makefile
QEMU_CABOODLE_DSTUB := $(HCP_UML_SRC)/qemu_init.Dockerfile
$(eval $(call pp_add_layer,\
	QEMU_CABOODLE,\
	QEMU_CABOODLE_BASE,\
	APPS,\
	$(hcp_pkg) uml-kbuild))

$(HCP_APPS_OUT)/qemu_caboodle.tar: $(HCP_QEMU_CABOODLE_TFILE)
$(HCP_APPS_OUT)/qemu_caboodle.tar: $(HCP_UML_SRC)/hcp_mkext4.sh
$(HCP_APPS_OUT)/qemu_caboodle.tar: $(HCP_BOOTSTRAP_CMD_DEPS)
$(HCP_APPS_OUT)/qemu_caboodle.tar:
	$Q$(HCP_BOOTSTRAP_CMD) dname2tar \
		$(HCP_QEMU_CABOODLE_DNAME) $@
HCP_QEMU_CABOODLE_IMG := $(HCP_APPS_OUT)/qemu_caboodle_img
$(HCP_QEMU_CABOODLE_IMG): | $(HCP_APPS_OUT)
MDIRS += $(HCP_QEMU_CABOODLE_IMG)
$(HCP_QEMU_CABOODLE_IMG)/disk: | $(HCP_QEMU_CABOODLE_IMG)
$(HCP_QEMU_CABOODLE_IMG)/disk: $(HCP_APPS_OUT)/qemu_caboodle.tar
$(HCP_QEMU_CABOODLE_IMG)/disk:
	$Q$(HCP_BOOTSTRAP_CMD) tar2img \
		$(HCP_APPS_OUT)/qemu_caboodle.tar $(HCP_QEMU_CABOODLE_IMG) \
		$(HCP_QEMU_DISK_MB) unused
ALL += $(HCP_QEMU_CABOODLE_IMG)/disk
HCP_DOCKER_IMGS += qemu_caboodle
ifneq (,$(wildcard $(HCP_APPS_OUT)/qemu_caboodle.tar $(HCP_QEMU_CABOODLE_IMG)))
clean_qemu_caboodle_pieces:
	$Qrm -f $(HCP_APPS_OUT)/qemu_caboodle.tar
	$Qrm -f $(HCP_QEMU_CABOODLE_IMG)/disk
	$Qrm -f $(HCP_QEMU_CABOODLE_IMG)/vmlinuz
	$Qrm -f $(HCP_QEMU_CABOODLE_IMG)/initrd.img
	$Qif test -d $(HCP_QEMU_CABOODLE_IMG); then rmdir $(HCP_QEMU_CABOODLE_IMG); fi
clean_qemu_caboodle: clean_qemu_caboodle_pieces
endif

endif # HCP_APP_QEMU
