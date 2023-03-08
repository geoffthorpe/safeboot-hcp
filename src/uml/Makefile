###########################
### Output parent directory
###########################

HCP_UML_SRC := $(HCP_SRC)/uml
HCP_UML_OUT := $(HCP_OUT)/uml
$(HCP_UML_OUT): | $(HCP_OUT)
MDIRS += $(HCP_UML_OUT)

###############
### UML_BUILDER - for compiling the kernel, modules, and 'myshutdown'
###############

uml_builder_packages := gcc make xz-utils flex bison bc kmod libvdeplug-dev

$(eval $(call pp_add_layer,\
	UML_BUILDER,\
	BASE,\
	UML,\
	$(uml_builder_packages),\
	$(HCP_UML_SRC)/builder.Dockerfile,\
	$(HCP_UML_SRC)/Makefile,\
	,\
	$(HCP_UML_SRC)/uml.kconfig $(HCP_UML_SRC)/myshutdown.c))

$(eval $(call cache_file_download,\
	KERNEL_SRC,\
	$(HCP_UML_KERNEL_FNAME),\
	kernel_src,\
	$(HCP_UML_BUILDER_OUT),\
	$(HCP_UML_KERNEL_URL)))

$(HCP_UML_BUILDER_TFILE): $(HCP_UML_BUILDER_OUT)/$(HCP_UML_KERNEL_FNAME)
$(HCP_UML_BUILDER_OUT)/$(HCP_UML_KERNEL_FNAME): | $(HCP_UML_BUILDER_OUT)

ifneq (,$(wildcard $(HCP_UML_BUILDER_OUT)/$(HCP_UML_KERNEL_FNAME)))
clean_uml_builder_kernelsrc:
	$Qrm $(HCP_UML_BUILDER_OUT)/$(HCP_UML_KERNEL_FNAME)
clean_uml_builder: clean_uml_builder_kernelsrc
endif

###########
### UML_RUN - for running user-mode-linux
###########

# TODO: actually, this runs QEMU too. Refactoring and renaming are in order...
# TODO: actually, is this even used now? hcp/qemu probably bypasses it ... need
# to sort things out and reconcile.

$(eval $(call pp_add_layer,\
	UML_RUN,\
	BASE,\
	UML,\
	vde2 qemu-system-x86,\
	$(HCP_UML_SRC)/run.Dockerfile,\
	$(HCP_UML_SRC)/Makefile $(HCP_UML_BUILDER_TFILE),\
	,\
	$(HCP_UML_SRC)/start.sh))

##############
### UML_IMAGER - for making filesystem and disk images
##############

# To support workflows where there shouldn't be _any_ privilege requirements,
# not even as a first-time thing, then we'll need a premade bootable image, at
# least to help build a fresh bootable image that can replace the premade one.
#
# If we have a bootstrap image available, the relevant image-building step (in
# hcp_mkext4.sh, as invoked on the host by the build) will launch a bootstrap
# container and defer the image-making operations into that. If a bootstrap
# image is _not_ available, hcp_mkext4.sh will instead try to execute the steps
# locally on the host using sudo, meaning the user will probably be prompted
# for a password.
#
# Note about caching - we use cache_file() to declare a read/inbound use of the
# cache for the 'bootstrapper' image, if it has one. Then, we use
# cache_file_update() to declare a write/outbound use of the cache for the
# resulting 'imager' image (so that gets invoked when running 'make
# cache_update'). Interestingly, we write the imager out as ...
# 'bootstrapper'!

HCP_UML_BOOTSTRAPPER_FNAME := uml_bootstrapper.ext4
$(eval $(call cache_file,\
	BOOTSTRAPPER_IMG,\
	$(HCP_UML_BOOTSTRAPPER_FNAME),\
	rootfs))

HCP_UML_IMAGER_FNAME := uml_imager.ext4
HCP_UML_IMAGER_PATH := $(HCP_UML_OUT)/$(HCP_UML_IMAGER_FNAME)
HCP_UML_IMAGER_MOUNT := $(HCP_UML_OUT)/uml_imager.mount
$(HCP_UML_IMAGER_PATH): | $(HCP_UML_OUT)
MDIRS += $(HCP_UML_IMAGER_MOUNT)
$(HCP_UML_IMAGER_MOUNT): | $(HCP_UML_OUT)
HCP_UML_IMAGER_TAR := $(HCP_UML_OUT)/uml_imager.tar
$(HCP_UML_IMAGER_TAR): | $(HCP_UML_OUT)

# The docker-generated rootfs used to create the imager image.
$(eval $(call pp_add_layer,\
	UML_IMAGER_ROOTFS,\
	BASE,\
	UML,\
	kmod isc-dhcp-client fdisk extlinux initramfs-tools,\
	$(HCP_UML_SRC)/imager.Dockerfile,\
	$(HCP_UML_SRC)/Makefile $(HCP_UML_BUILDER_TFILE),\
	,\
	$(HCP_UML_SRC)/init.sh $(HCP_UML_SRC)/hcp_mkext4.sh))

# - the rootfs tarball pulled from the docker daemon
$(HCP_UML_IMAGER_TAR): $(HCP_UML_IMAGER_ROOTFS_TFILE)
$(HCP_UML_IMAGER_TAR): $(HCP_UML_SRC)/hcp_mkext4.sh
$(HCP_UML_IMAGER_TAR):
	$Q$(HCP_UML_SRC)/hcp_mkext4.sh \
		dname2tar \
			$(HCP_UML_IMAGER_ROOTFS_DNAME) \
			$(HCP_UML_IMAGER_TAR)

$(HCP_UML_IMAGER_PATH): | $(HCP_UML_IMAGER_MOUNT)
$(HCP_UML_IMAGER_PATH): $(HCP_UML_IMAGER_TAR)
ifneq (,$(HCP_CACHE_BOOTSTRAPPER_IMG_FILE))
$(HCP_UML_IMAGER_PATH): $(HCP_UML_RUN_TFILE)
endif
$(HCP_UML_IMAGER_PATH):
	$QBOOTSTRAP_IMG="$(HCP_CACHE_BOOTSTRAPPER_IMG_FILE)" \
			BOOTSTRAP_DNAME="$(HCP_UML_RUN_DNAME)" \
		$(HCP_UML_SRC)/hcp_mkext4.sh \
			tar2ext4 \
				$(HCP_UML_IMAGER_TAR) \
				$(HCP_UML_IMAGER_PATH) \
				$(HCP_UML_EXT4_SIZE) \
				$(HCP_UML_IMAGER_MOUNT)

# This pushes the resulting uml_imager.ext4 into the cache, but as
# uml_bootstrapper.ext4!! This is why we use an empty output from cache_file()
# to handle the case where uml_bootstrapper.ext4 doesn't exist, because if we
# instead declared a dependency on the bootstrapper image, the dependencies
# would go circular.
$(eval $(call cache_file_update,\
	IMAGER,\
	$(HCP_UML_BOOTSTRAPPER_FNAME),\
	rootfs,\
	$(HCP_UML_OUT)/$(HCP_UML_IMAGER_FNAME)))

# Parent-level cleanup
ifneq (,$(wildcard $(HCP_UML_OUT)))
clean_uml:
	$Qrm -f $(HCP_UML_IMAGER_PATH)
	$Qif test -d $(HCP_UML_IMAGER_MOUNT); then \
		rmdir $(HCP_UML_IMAGER_MOUNT); \
	fi
	$Qrm -f $(HCP_UML_IMAGER_TAR)
	$Qrmdir $(HCP_UML_OUT)
clean: clean_uml
endif
