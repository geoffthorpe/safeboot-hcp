# If HCP_CACHE is undefined, all rules are disabled no matter what. Otherwise,
# all the rules will be enabled by default unless HCP_CACHE_DEFAULT_DISABLE is
# defined, in which case they're disabled by default. An individual rule can be
# enabled (if the default is to disable them) or disabled (if the default is to
# enable them) by respectively defining HCP_CACHE_ENABLE_<RULENAME> or
# HCP_CACHE_DISABLE_<RULENAME>.
define __cache_test_enable
$(eval upper_name := $(strip $1))
$(eval HCP_CACHE_ISENABLED :=)
ifdef HCP_CACHE
ifdef HCP_CACHE_DEFAULT_DISABLE
ifdef HCP_CACHE_ENABLE_$(upper_name)
$(eval HCP_CACHE_$(upper_name)_ISENABLED := 1)
endif # HCP_CACHE_ENABLE_$(upper_name)
else # !HCP_CACHE_DEFAULT_DISABLE
ifndef HCP_CACHE_DISABLE_$(upper_name)
$(eval HCP_CACHE_$(upper_name)_ISENABLED := 1)
endif # !HCP_CACHE_DISABLE_$(upper_name)
endif # !HCP_CACHE_DEFAULT_DISABLE
endif # HCP_CACHE
endef

# cache_file_get() - use a cached file, no update to the cache
# $1 - upper_name - symbolic name.
# $2 - fname - just the asset filename, without any path or URL components
# $3 - cachedir - dirpath relative to $(HCP_CACHE) for caching the file
# If rule is enabled;
# - If $(HCP_CACHE)/$(cachedir)/$(fname) exists
#     - HCP_CACHE_$(upper_name)_FILE := $(HCP_CACHE)/$(cachedir)/$(fname)
#   else
#     - HCP_CACHE_$(upper_name)_FILE is set empty
# If rule is disabled;
# - HCP_CACHE_$(upper_name)_FILE is set empty
define cache_file_get
$(eval upper_name := $(strip $1))
$(eval fname := $(strip $2))
$(eval cachepath := $(HCP_CACHE)/$(strip $3)/$(fname))
$(eval $(call __cache_test_enable,$(upper_name)))
$(eval HCP_CACHE_$(upper_name)_FILE :=)
ifdef HCP_CACHE_$(upper_name)_ISENABLED
$(if $(wildcard $(cachepath)),$(eval HCP_CACHE_$(upper_name)_FILE := $(cachepath)))
endif
endef

# cache_file_update() - push results into the cache
# $1 - upper_name - symbolic name.
# $2 - fname - the asset filename to store in the cache
# $3 - cachedir - dirpath relative to $(HCP_CACHE) for caching the file
# $4 - outpath - full path of the file to be cached (should sit inside
#                $(HCP_OUT)).
# If rule is enabled;
# - $(HCP_CACHE)/$(cachedir)/$(fname) depends on $(outpath), from which it will
#   be updated.
# - $(HCP_CACHE)/$(cachedir)/$(fname) is made a dependency of 'cache_update'.
# Note, we resist the temptation to create a dependency of $(cachedir)/$(fname)
# on $(outpath) in order to only update the cache copy if the locally-built
# copy is newer. Reason: lots of things will declare dependencies on (and use)
# $(cachedir)/$(fname) because that's what <pkg>_LOCAL_PATH gets pointed to by
# the cache_file_get() call --> we'll hardly ever use (benefit from) the cache
# copy without first regenerating and updating it! Instead, we make
# 'cache_update' always do work (rather than basing itself off dependencies)
# and we update the cache based on file contents rather than modification times
# (which is arguably better, seeing as we're avoiding dependencies anyway).  So
# .. instead, we make the symbolic target (cache_update_<pkg>) depend on the
# built packages, so that if the build is out of date, it rebuilds _here_
# rather than in other contexts, where the cache'd package should be used and
# rebuilding shouldn't happen.
define cache_file_update
$(eval upper_name := $(strip $1))
$(eval fname := $(strip $2))
$(eval cachedir := $(HCP_CACHE)/$(strip $3))
$(eval outpath := $(strip $4))
$(eval $(call __cache_test_enable,$(upper_name)))
ifdef HCP_CACHE_$(upper_name)_ISENABLED
cache_update_$(upper_name): $(outpath)
	$Qif cmp "$(cachedir)/$(fname)" "$(outpath)" > /dev/null 2>&1; then \
		echo "$(upper_name): cache copy is already up-to-date"; \
	else \
		echo "$(upper_name): storing to cache"; \
		mkdir -p $(cachedir); \
		cp "$(outpath)" "$(cachedir)/$(fname)"; \
	fi
cache_update: cache_update_$(upper_name)
endif
endef
cache_update:

# cache_file_download()
# $1 - upper_name - symbolic name.
# $2 - fname - just the asset filename, without any path or URL components
# $3 - cachedir - dirpath relative to $(HCP_CACHE) for caching the file
# $4 - outdir - full dirpath where the resulting file is needed (should sit
#               inside $(HCP_OUT)).
# $5 - url - the URL the file can be downloaded from.
# If rule is enabled;
# - HCP_CACHE_$(upper_name)_FILE := $(HCP_CACHE)/$(cachedir)/$(fname)
# - a rule is provided for $(HCP_CACHE_$(upper_name)_FILE that will download
#   the file from the given URL.
# If the rule is disabled;
# - HCP_CACHE_$(upper_name)_FILE is set empty
# - a rule is provided for $(outdir)/$(fname) that will download the file from
#   the given URL.
define cache_file_download
$(eval upper_name := $(strip $1))
$(eval fname := $(strip $2))
$(eval cachepath := $(HCP_CACHE)/$(strip $3))
$(eval outdir := $(strip $4))
$(eval url := $(strip $5))
$(eval $(call __cache_test_enable,$(upper_name)))
ifdef HCP_CACHE_$(upper_name)_ISENABLED
$(eval HCP_CACHE_$(upper_name)_FILE := $(cachepath)/$(fname))
$(cachepath)/$(fname):
	$Qecho "$(upper_name): downloading to cache"
	$Qmkdir -p $(cachepath)
	$Qwget -O $(cachepath)/$(fname) $(url)
$(outdir)/$(fname): | $(cachepath)/$(fname)
	$Qcp $(cachepath)/$(fname) $(outdir)/$(fname)
cache_update: $(cachepath)/$(fname)
else
$(eval HCP_CACHE_$(upper_name)_FILE := $(outdir)/$(fname))
$(outdir)/$(fname):
	$Qecho "$(upper_name): downloading (not to cache)"
	$Qmkdir -p $(outdir)
	$Qwget -O $(outdir)/$(fname) $(url)
endif
endef
