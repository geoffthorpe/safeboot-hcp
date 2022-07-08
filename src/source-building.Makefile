# This instantiates all the support to bootstrap, configure, compile, install,
# and clean a given codebase, named by $2, which is expected to live in $9. Any
# dependencies on other codebases are listed in $3, in which case the the
# configure step for $2 will depend on the install step for each item in $3. $4
# specifies a file that is guaranteed to exist in the top-level directory of
# the codebase prior to bootstrapping, that we can copy user/group ownership
# from. Other arguments provide command lines for the various processing steps
# of the codebase;
# $1 = source-builder name, as passed as $1 to source_builder_initialize.
# $2 = name of codebase,
# $3 = codebases that must be installed before we can configure.
# $4 = path to source
# $5 = reference file (relative to codebase top-level) for chown-ership of files.
# $6 = command line to bootstrap the codebase
# $7 = command line to configure the codebase
# $8 = command line to compile the codebase
# $9 = command line to install the codebase
# $10 = if non-empty, disable use of "git reset", even if the source-set
#       enables it.
define source_builder_add
$(eval N := $(strip $1))
$(eval LOCAL_NAME := $(strip $2))
$(eval LOCAL_DEPS := $(strip $3))
$(eval LOCAL_SRCPATH := $(strip $4))
$(eval LOCAL_CHOWNER := $(strip $5))
$(eval LOCAL_CHOWN := trap '/hcp/base/chowner.sh $(LOCAL_CHOWNER) .' EXIT ; cd /src-$(LOCAL_NAME))
$(eval LOCAL_BOOTSTRAP := $(LOCAL_CHOWN) ; $(strip $6))
$(eval LOCAL_CONFIGURE := $(LOCAL_CHOWN) ; $(strip $7))
$(eval LOCAL_COMPILE := $(LOCAL_CHOWN) ; $(strip $8))
$(eval LOCAL_INSTALL := $(LOCAL_CHOWN) ; $(strip $9))
$(eval LOCAL_RESET_DISABLE := $(strip $(10)))
$(eval HCP_SOURCE_MODULES_$N += $(LOCAL_NAME))
$(eval LOCAL_RUN := $(HCP_SOURCE_DOCKER_RUN_$N))
$(eval LOCAL_RUN += --mount type=bind,source=$(LOCAL_SRCPATH),destination=/src-$(LOCAL_NAME))
$(eval LOCAL_RUN += $(HCP_BUILDER_DNAME))
$(eval LOCAL_RUN += bash -c)
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).bootstrapped: $(LOCAL_SRCPATH)/$(LOCAL_CHOWNER)
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).bootstrapped: $(HCP_SOURCE_BUILDER_DEP_$N)
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).bootstrapped: | $(HCP_SOURCE_INSTALL_TOUCH_$N)
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).bootstrapped:
	$Q$(LOCAL_RUN) "$(LOCAL_BOOTSTRAP)"
	$Qtouch $$@
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).configured: $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).bootstrapped
$(foreach i,$(strip $(LOCAL_DEPS)),
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).configured: $(HCP_SOURCE_OUT_$N)/$i.installed
)
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).configured:
	$Q$(LOCAL_RUN) "$(LOCAL_CONFIGURE)"
	$Qtouch $$@
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).compiled: $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).configured
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).compiled:
	$Q$(LOCAL_RUN) "$(LOCAL_COMPILE)"
	$Qtouch $$@
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).installed: $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).compiled
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).installed:
	$Q$(LOCAL_RUN) "$(LOCAL_INSTALL)"
	$Qtouch $$@
$(if $(LOCAL_RESET_DISABLE),,
$(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).reset:
	$Q(cd $(LOCAL_SRCPATH) && git clean -f -d -x && git reset --hard)
	$Qrm -f $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).*
$(eval HCP_SOURCE_RESETS_$N += $(LOCAL_NAME))
)
$(if $(HCP_SOURCE_XTRATARGETS_$N),
$N_$(LOCAL_NAME): $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).installed
$N_$(LOCAL_NAME)_bootstrap: $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).bootstrapped
$N_$(LOCAL_NAME)_configure: $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).configured
$N_$(LOCAL_NAME)_compile: $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).compiled
$N_$(LOCAL_NAME)_install: $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).installed
$N_$(LOCAL_NAME)_reset: $(HCP_SOURCE_OUT_$N)/$(LOCAL_NAME).reset
)
endef

# $1 = name, for use in naming dependency targets, docker volumes, etc.
# $2 = tarball name, for use in hcp/apps/*/Makefile calls to app_image()
# $3 = installation path/prefix for all assets installed by the source set (and
#      mount point for the volume used to house them, so anything installed
#      anywhere else gets deliberately lost). Note, this must begin with "/".
# $4 = if non-empty, enable "submodule reset" on this source set. I.e. assume
#      it's a git submodule and should be forcefully reset to current git
#      version (removing all source modifications and build artifacts) when
#      running the corresponding "reset" Makefile target.
# $5 = if non-empty, enabled "extra targets" on this source set. I.e. fine-grain
#      bootstrap/configure/compile/install targets for each codebase.
define source_builder_initialize
$(eval N := $(strip $1))
$(eval HCP_SOURCE_OUT_$N := $(HCP_OUT)/sbuilder_$N)
$(eval HCP_SOURCE_INSTALL_VOLUME_$N := $(HCP_IMAGE_PREFIX)source_$N)
$(eval HCP_SOURCE_INSTALL_TOUCH_$N := $(HCP_SOURCE_OUT_$N)/vol.created)
$(eval HCP_SOURCE_TGZ_$N := $(strip $2))
$(eval HCP_SOURCE_INSTALL_DEST_$N := $(strip $3))
$(eval HCP_SOURCE_RESET_$N := $(strip $4))
$(eval HCP_SOURCE_XTRATARGETS_$N := $(strip $5))
$(HCP_SOURCE_OUT_$N): | $(HCP_OUT)
MDIRS += $(HCP_SOURCE_OUT_$N)
$(HCP_SOURCE_INSTALL_TOUCH_$N): | $(HCP_SOURCE_OUT_$N)
	$Qdocker volume create $(HCP_SOURCE_INSTALL_VOLUME_$N)
	$Qtouch $$@
$(eval HCP_SOURCE_DOCKER_RUN_$N := \
	docker run -i --rm --label $(HCP_IMAGE_PREFIX)all=1 \
	--mount type=volume,source=$(HCP_SOURCE_INSTALL_VOLUME_$N),destination=$(HCP_SOURCE_INSTALL_DEST_$N))
ifneq (,$(LAZY))
HCP_SOURCE_BUILDER_DEP_$N := | $(HCP_BUILDER_OUT)/built
else
HCP_SOURCE_BUILDER_DEP_$N := $(HCP_BUILDER_OUT)/built
endif
endef

# $1 = name, as per source_builder_initialize
# Note, HCP_SOURCE_RESULT_$N is the path the resulting tarball/Dockerfile pair,
# minus the ".tar.gz"/".Dockerfile" suffixes obviously.
define source_builder_finalize
$(eval N := $(strip $1))
$(eval HCP_SOURCE_INSTALL_RUN_$N := $(HCP_SOURCE_DOCKER_RUN_$N) \
	--mount type=bind,source=$(HCP_SOURCE_OUT_$N),destination=/put_it_here \
	$(HCP_BUILDER_DNAME) \
	bash -c)
$(eval HCP_SOURCE_TGZ_CMD_$N := cd /put_it_here ;)
$(eval HCP_SOURCE_TGZ_CMD_$N += tar zcf $(HCP_SOURCE_TGZ_$N).tar.gz $(HCP_SOURCE_INSTALL_DEST_$N) ;)
$(eval HCP_SOURCE_TGZ_CMD_$N += /hcp/base/chowner.sh vol.created $(HCP_SOURCE_TGZ_$N).tar.gz)
$(eval HCP_SOURCE_RESULT_$N := $(HCP_SOURCE_OUT_$N)/$(HCP_SOURCE_TGZ_$N))
$(HCP_SOURCE_RESULT_$N).tar.gz: $(foreach i,$(HCP_SOURCE_MODULES_$N),$(HCP_SOURCE_OUT_$N)/$i.installed)
$(HCP_SOURCE_RESULT_$N).tar.gz:
	$Q$(HCP_SOURCE_INSTALL_RUN_$N) "$(HCP_SOURCE_TGZ_CMD_$N)"
$(HCP_SOURCE_RESULT_$N).Dockerfile: $(HCP_SOURCE_RESULT_$N).tar.gz
$(HCP_SOURCE_RESULT_$N).Dockerfile:
	$Qecho "COPY sbuilder_$N/$(HCP_SOURCE_TGZ_$N).tar.gz /" > $$@
	$Qecho "RUN tar zxf $(HCP_SOURCE_TGZ_$N).tar.gz && rm $(HCP_SOURCE_TGZ_$N).tar.gz" >> $$@
$N: $(HCP_SOURCE_RESULT_$N).tar.gz
ALL += $(HCP_SOURCE_RESULT_$N).tar.gz
ifneq (,$(HCP_SOURCE_RESET_$N))
$N_reset: $(foreach i,$(HCP_SOURCE_RESETS_$N),$(HCP_SOURCE_OUT_$N)/$i.reset)
endif
ifneq (,$(wildcard $(HCP_SOURCE_OUT_$N)))
ifneq (,$(HCP_SOURCE_RESET_$N))
clean_$N: $(foreach i,$(HCP_SOURCE_RESETS_$N),$(HCP_SOURCE_OUT_$N)/$i.reset)
endif
clean_$N:
	$Qrm -f $(HCP_SOURCE_RESULT_$N).tar.gz
	$Qrm -f $(HCP_SOURCE_RESULT_$N).Dockerfile
ifneq (,$(wildcard $(HCP_SOURCE_INSTALL_TOUCH_$N)))
	$Qdocker volume rm $(HCP_SOURCE_INSTALL_VOLUME_$N)
	$Qrm $(HCP_SOURCE_INSTALL_TOUCH_$N)
endif
	$Qrm -rf $(HCP_SOURCE_OUT_$N)
clean_builder: clean_$N
endif
endef
