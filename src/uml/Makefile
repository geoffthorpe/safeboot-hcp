###########################
### Output parent directory
###########################

# Our current ordering requires that 'uml_builder' be declared before 'uml',
# but the former really doesn't want to be a parent of the latter, and having
# too many siblings bloats the output tree and makes the story around "clean_*"
# targets too weird. So, we create an output directory to serve as a parent for
# the others.
HCP_UML_SRC := $(HCP_SRC)/uml
HCP_UML_OUT := $(HCP_OUT)/uml
$(HCP_UML_OUT): | $(HCP_OUT)
MDIRS += $(HCP_UML_OUT)
ifneq (,$(wildcard $(HCP_UML_OUT)))
clean_uml:
	$Qrmdir $(HCP_UML_OUT)
clean: clean_uml
endif

###############
### UML_BUILDER - for compiling the kernel, modules, and 'myshutdown'
###############

$(eval $(call pp_add_layer,\
	UML_BUILDER,\
	BUILDER,\
	UML,\
	bc kmod,\
	$(HCP_UML_SRC)/builder.Dockerfile,\
	$(HCP_UML_SRC)/Makefile,\
	,\
	,\
	$(HCP_UML_SRC)/uml.kconfig $(HCP_UML_SRC)/myshutdown.c))

# UML_BUILDER is dependent on this kernel source.
HCP_UML_KERNEL_LOCAL := $(HCP_UML_BUILDER_OUT)/$(HCP_UML_KERNEL_FNAME)
$(HCP_UML_BUILDER_TFILE): $(HCP_UML_KERNEL_LOCAL)
$(HCP_UML_KERNEL_LOCAL): | $(HCP_UML_BUILDER_OUT)

# Deal with the possible cache config and what-not.
$(eval $(call cache_add_dir,KERNEL_SRC))
$(eval $(call cache_add_asset,KERNEL_SRC,UML_KERNEL_SRC,$(HCP_UML_KERNEL_FNAME)))
$(eval $(call cache_consume_asset,UML_KERNEL_SRC,$(HCP_UML_BUILDER_OUT)))

# If HCP_CACHE_RULE_UML_KERNEL_SRC is set, we generate rules to pull the kernel
# source to that path.
ifdef HCP_CACHE_RULE_UML_KERNEL_SRC
$(HCP_CACHE_RULE_UML_KERNEL_SRC):
	$Qecho "Downloading kernel: $(HCP_UML_KERNEL_URL)"
	$Qwget -O $@ $(HCP_UML_KERNEL_URL)
endif

uml_builder_getkernel: $(HCP_UML_KERNEL_LOCAL)
ifneq (,$(wildcard $(HCP_UML_KERNEL_LOCAL)))
clean_uml_builder_getkernel:
	$Qrm $(HCP_UML_KERNEL_LOCAL)
clean_uml_builder: clean_uml_builder_getkernel
endif

###########
### UML_RUN - for running user-mode-linux
###########

$(eval $(call pp_add_layer,\
	UML_RUN,\
	BASE,\
	UML,\
	,\
	$(HCP_UML_SRC)/run.Dockerfile,\
	$(HCP_UML_SRC)/Makefile,\
	,\
	,\
	$(HCP_UML_SRC)/start.sh))

# run.Dockerfile pulls the compiled UML kernel from HCP_UML_BUILDER, so note
# that dependency;
$(HCP_UML_RUN_TFILE): $(HCP_UML_BUILDER_TFILE)

#######################
### Bootable disk image - docker image -> tarball -> ext4 image
#######################

HCP_UML_BOOTSTRAPPER_FNAME := uml_bootstrapper.ext4
HCP_UML_BOOTSTRAPPER_PATH := $(HCP_UML_OUT)/$(HCP_UML_BOOTSTRAPPER_FNAME)
$(HCP_UML_BOOTSTRAPPER_PATH): | $(HCP_UML_OUT)
HCP_UML_BOOTSTRAPPER_MOUNT := $(HCP_UML_OUT)/uml_bootstrapper.mount
MDIRS += $(HCP_UML_BOOTSTRAPPER_MOUNT)
HCP_UML_BOOTSTRAPPER_TAR := $(HCP_UML_OUT)/uml_bootstrapper.tar

$(eval $(call cache_add_dir,ROOTFS))
$(eval $(call cache_add_asset,ROOTFS,UML_BOOTSTRAPPER,\
			$(HCP_UML_BOOTSTRAPPER_FNAME)))
$(eval $(call cache_consume_asset,UML_BOOTSTRAPPER,$(HCP_UML_OUT)))

# The docker-generated rootfs used to create the bootstrapper image. Note, this
# is defined irrespective of the HCP_CACHE_RULE_UML_BOOTSTRAPPER conditional
# (below) because even if we're using a cached image (and so don't need the
# rules for generating it), we may still need the corresponding cleanup rules
# if there is stuff lying around to be cleaned up. (Eg. from previously
# building and caching the bootstrapper!)
$(eval $(call pp_add_layer,\
	UML_BOOTSTRAPPER_ROOTFS,\
	BASE,\
	UML,\
	kmod,\
	$(HCP_UML_SRC)/bootstrapper.Dockerfile,\
	$(HCP_UML_SRC)/Makefile,\
	,\
	,\
	$(HCP_UML_SRC)/init.sh))

# The HCP_CACHE_RULE_* output tells us if we have to generate rules to generate
# the bootstrapper image, and what path it should be generated at. By
# dependency, this also controls the logic to create the rootfs tarball, the
# mount directory, etc.
ifdef HCP_CACHE_RULE_UML_BOOTSTRAPPER

# bootstrapper.Dockerfile pulls files from HCP_UML_BUILDER;
$(HCP_UML_BOOTSTRAPPER_ROOTFS_TFILE): $(HCP_UML_BUILDER_TFILE)

# - the mount directory for disk image production
$(HCP_UML_BOOTSTRAPPER_MOUNT): | $(HCP_UML_OUT)

# - the rootfs tarball pulled from the docker daemon
$(HCP_UML_BOOTSTRAPPER_TAR): | $(HCP_UML_OUT)
$(HCP_UML_BOOTSTRAPPER_TAR): $(HCP_UML_BOOTSTRAPPER_ROOTFS_TFILE)
$(HCP_UML_BOOTSTRAPPER_TAR): $(HCP_UML_SRC)/hcp_mkext4.sh
$(HCP_UML_BOOTSTRAPPER_TAR):
	$Q$(HCP_UML_SRC)/hcp_mkext4.sh \
		dname2tar \
			$(HCP_UML_BOOTSTRAPPER_ROOTFS_DNAME) \
			$@

# Unlike other rootfs-productions, this one does _not_ depend on UML_RUN,
# because this is to produce the bootstrapper rootfs. Ie. you can use UML _and_
# the bootstrapper to produce other rootfs, but not the bootstrapper itself.
# That's also why we set BOOTSTRAP_IMG empty, so that hcp_mkext4.sh doesn't try
# to do the work inside a VM.
$(HCP_CACHE_RULE_UML_BOOTSTRAPPER): | $(HCP_UML_BOOTSTRAPPER_MOUNT)
$(HCP_CACHE_RULE_UML_BOOTSTRAPPER): $(HCP_UML_BOOTSTRAPPER_TAR)
$(HCP_CACHE_RULE_UML_BOOTSTRAPPER):
	$QBOOTSTRAP_IMG="" BOOTSTRAP_DNAME="" \
		$(HCP_UML_SRC)/hcp_mkext4.sh \
			tar2ext4 \
				$(HCP_UML_BOOTSTRAPPER_TAR) \
				$@ \
				$(HCP_UML_EXT4_SIZE) \
				$(HCP_UML_BOOTSTRAPPER_MOUNT)
endif

# The cleanup rules depend on whether the files exist, not on whether we do or
# don't have rules to build that which is being cleaned up.
ifneq (,$(wildcard $(HCP_UML_BOOTSTRAPPER_PATH)))
clean_uml_bootstrapper:
	$Qrm $(HCP_UML_BOOTSTRAPPER_PATH)
clean_uml: clean_uml_bootstrapper
endif
ifneq (,$(wildcard $(HCP_UML_BOOTSTRAPPER_TAR)))
clean_uml_bootstrapper_tar:
	$Qrm $(HCP_UML_BOOTSTRAPPER_TAR)
clean_uml: clean_uml_bootstrapper_tar
endif
ifneq (,$(wildcard $(HCP_UML_BOOTSTRAPPER_MOUNT)))
clean_uml_bootstrapper_mount:
	$Qrmdir $(HCP_UML_BOOTSTRAPPER_MOUNT)
clean_uml: clean_uml_bootstrapper_mount
endif

# The bootstrapper disk image depends on everything else except UML_RUN, so we
# use those two for "make uml", and include them in "make all"
uml: $(HCP_UML_BOOTSTRAPPER_PATH) $(HCP_UML_RUN_TFILE)
ALL += $(HCP_UML_BOOTSTRAPPER_PATH) $(HCP_UML_RUN_TFILE)
