###########################
### Output parent directory
###########################

HCP_UML_SRC := $(HCP_SRC)/uml
HCP_UML_OUT := $(HCP_OUT)/uml
$(HCP_UML_OUT): | $(HCP_OUT)
MDIRS += $(HCP_UML_OUT)

###############
### UML_BUILDER - for compiling kernel+modules, 'myshutdown', 'sd_notify_ready'
###############

uml_builder_packages := gcc make xz-utils flex bison bc kmod libvdeplug-dev
uml_builder_packages += libsystemd-dev

$(eval $(call pp_add_layer,\
	UML_BUILDER,\
	BUILDER,\
	UML,\
	$(uml_builder_packages),\
	$(HCP_UML_SRC)/kbuild.Dockerfile,\
	$(HCP_UML_SRC)/Makefile,\
	,\
	$(HCP_UML_SRC)/uml.kconfig $(HCP_UML_SRC)/myshutdown.c\
		$(HCP_UML_SRC)/sd_notify_ready.c\
		$(HCP_UML_SRC)/kbuild.sh))

####################################
# Build the UML kernel and modules #
####################################

HCP_UML_KBUILD_OUT := $(HCP_UML_OUT)/kbuild
$(HCP_UML_KBUILD_OUT): | $(HCP_UML_OUT)
MDIRS += $(HCP_UML_KBUILD_OUT)

$(eval $(call cache_file_download,\
	KERNEL_SRC,\
	$(HCP_UML_KERNEL_FNAME),\
	kernel_src,\
	$(HCP_UML_KBUILD_OUT),\
	$(HCP_UML_KERNEL_URL)))
$(eval $(call cache_file_update,\
	KERNEL_SRC,\
	$(HCP_UML_KERNEL_FNAME),\
	kernel_src,\
	$(HCP_UML_KBUILD_OUT)/$(HCP_UML_KERNEL_FNAME)))

# Add a builder target, and use our "UML_BUILDER" layer to build it (it's
# derived from the default "BUILDER").
uml-kbuild_BUILDER := UML_BUILDER
# And prep the env-vars that /kbuild.sh will expect
uml-kbuild_env := KERNEL_DIR=linux-$(HCP_UML_KERNEL_VERSION)
uml-kbuild_env += KERNEL_BALL=$(HCP_UML_KERNEL_FNAME)
uml-kbuild_env += KERNEL_CONF=/uml.kconfig
# Note, we do all the work in the install step primarily to avoid having the
# kernel expanded into persistent storage, and pay the costs of each
# container-exit doing a "chowner" run as the bootsrap, configure, compile, and
# install steps run. It's just one run, and the source is extracted and deleted
# in that run, so no need to fix FS ownerships.
$(eval $(call builder_add,\
	uml-kbuild,\
	$(HCP_UML_KBUILD_OUT),\
	,\
	,\
	,\
	,\
	,\
	$(uml-kbuild_env) /kbuild.sh,\
	))

# Make sure our persistent directory exists and contains the kernel source
# before the bootstrap step runs (ie. the first attempt to mount the
# directory). (Use a hard link rather than cp, saves disk.)
$(HCP_BUILD_DEP_UML-KBUILD_BOOTSTRAPPED): | $(HCP_UML_KBUILD_OUT)/$(HCP_UML_KERNEL_FNAME)
$(HCP_UML_KBUILD_OUT)/$(HCP_UML_KERNEL_FNAME): | $(HCP_UML_KBUILD_OUT)

# And disappear before the parent directory does. (Note, we can't use
# "clean_uml-kbuild", the builder_add() call already defines that for something
# else.)
ifneq (,$(wildcard $(HCP_UML_KBUILD_OUT)))
clean_uml-kbuild_dir:
	$Qrm -rf $(HCP_UML_KBUILD_OUT)/
clean_uml: clean_uml-kbuild_dir
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
	vde2 qemu-system-x86 uml-kbuild,\
	$(HCP_UML_SRC)/run.Dockerfile,\
	$(HCP_UML_SRC)/Makefile $(HCP_UML_BUILDER_TFILE),\
	,\
	$(HCP_UML_SRC)/start.sh))

###########################
### UML_BOOTSTRAPPER_ROOTFS - for making filesystem and disk images
###########################

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

# The docker-generated rootfs used to create the imager image.
$(eval $(call pp_add_layer,\
	UML_BOOTSTRAPPER_ROOTFS,\
	BASE,\
	UML,\
	kmod isc-dhcp-client fdisk extlinux initramfs-tools uml-kbuild,\
	$(HCP_UML_SRC)/bootstrapper.Dockerfile,\
	$(HCP_UML_SRC)/Makefile $(HCP_UML_BUILDER_TFILE),\
	,\
	$(HCP_UML_SRC)/bootstrapper_init.sh $(HCP_UML_SRC)/hcp_mkext4.sh))

HCP_UML_BOOTSTRAPPER_FNAME := uml_bootstrapper.ext4
HCP_UML_BOOTSTRAPPER_BUILT_PATH := $(HCP_UML_OUT)/$(HCP_UML_BOOTSTRAPPER_FNAME)
$(HCP_UML_BOOTSTRAPPER_BUILT_PATH): | $(HCP_UML_OUT)
HCP_UML_BOOTSTRAPPER_TAR := $(HCP_UML_OUT)/uml_bootstrapper.tar
$(HCP_UML_BOOTSTRAPPER_TAR): | $(HCP_UML_OUT)

$(eval $(call cache_file_get,\
	BOOTSTRAPPER_EXT4,\
	$(HCP_UML_BOOTSTRAPPER_FNAME),\
	rootfs))
$(eval $(call cache_file_update,\
	BOOTSTRAPPER_EXT4,\
	$(HCP_UML_BOOTSTRAPPER_FNAME),\
	rootfs,\
	$(HCP_UML_BOOTSTRAPPER_BUILT_PATH)))
$(if $(HCP_UML_BOOTSTRAPPER_LOCAL_PATH),,\
	$(eval HCP_UML_BOOTSTRAPPER_LOCAL_PATH := $(HCP_CACHE_BOOTSTRAPPER_EXT4_FILE)))
$(if $(HCP_UML_BOOTSTRAPPER_LOCAL_PATH),,\
	$(eval HCP_UML_BOOTSTRAPPER_LOCAL_PATH := $(HCP_UML_BOOTSTRAPPER_EXT4_BUILT_PATH)))

# - the rootfs tarball pulled from the docker daemon
$(HCP_UML_BOOTSTRAPPER_TAR): $(HCP_UML_BOOTSTRAPPER_ROOTFS_TFILE)
$(HCP_UML_BOOTSTRAPPER_TAR): $(HCP_UML_SRC)/hcp_mkext4.sh
$(HCP_UML_BOOTSTRAPPER_TAR):
	$Q$(HCP_UML_SRC)/hcp_mkext4.sh \
		dname2tar \
			$(HCP_UML_BOOTSTRAPPER_ROOTFS_DNAME) \
			$(HCP_UML_BOOTSTRAPPER_TAR)

$(HCP_UML_BOOTSTRAPPER_BUILT_PATH): $(HCP_UML_BOOTSTRAPPER_TAR)
ifneq (,$(HCP_CACHE_BOOTSTRAPPER_EXT4_FILE))
# If you have a bootstrapper fs image in your cache, you can boot it with UML
# and (because you are superuser in the ficitious VFS that results) use that to
# generate a newer bootstrapper fs image (ie. from source), without requiring
# special privs on the host. But if you don't have a prior bootstrapper image,
# hcp_mkext4.sh tries to generate the fs image by issuing 'sudo
# {mount,losetup,etc}' commands directly in the host environment (ie. as a
# subprocess of "make"). Note that, in the UML case, you need the UML_RUN
# container image to handle booting up the UML instance, whereas the fallback
# case runs directly on the host (running 'sudo mount' from a container seems
# problematic than hoping the host has usable tools installed and that the user
# has the necessary sudo privs).
$(HCP_UML_BOOTSTRAPPER_BUILT_PATH): $(HCP_UML_RUN_TFILE)
endif
$(HCP_UML_BOOTSTRAPPER_BUILT_PATH):
	$QBOOTSTRAP_IMG="$(HCP_CACHE_BOOTSTRAPPER_EXT4_FILE)" \
			BOOTSTRAP_DNAME="$(HCP_UML_RUN_DNAME)" \
		$(HCP_UML_SRC)/hcp_mkext4.sh \
			tar2ext4 \
				$(HCP_UML_BOOTSTRAPPER_TAR) \
				$(HCP_UML_BOOTSTRAPPER_BUILT_PATH) \
				$(HCP_UML_EXT4_MB)

# Other image-producing rules should use this command and append their
# arguments to it.
$(eval HCP_BOOTSTRAP_CMD := \
	BOOTSTRAP_IMG="$(HCP_UML_BOOTSTRAPPER_BUILT_PATH)" \
	BOOTSTRAP_DNAME="$(HCP_UML_RUN_DNAME)" \
	$(HCP_UML_SRC)/hcp_mkext4.sh)

# And they should declare dependencies on this;
$(eval HCP_BOOTSTRAP_CMD_DEPS := $(HCP_UML_BOOTSTRAPPER_BUILT_PATH) \
				$(HCP_UML_RUN_TFILE))

# Parent-level cleanup
ifneq (,$(wildcard $(HCP_UML_OUT)))
clean_uml:
	$Qrm -f $(HCP_UML_BOOTSTRAPPER_BUILT_PATH)
	$Qrm -f $(HCP_UML_BOOTSTRAPPER_TAR)
	$Qrmdir $(HCP_UML_OUT)
clean: clean_uml
endif
