# NB: we intentionally bypass MDIRS and the other niceties normally associated
# with HCP creating (and cleaning) output directories. The 'cache' stuff is
# supposed to persist, it is precisely the exception we want to our normal mode
# of cleaning up after ourselves. So if we download a big kernel source
# tarball, or retain a cached copy of a disk image that took a long time to
# build, it will survive "make clean" and can even be shared between otherwise
# independent environments. As such, any detection/creation of directories is
# done when the registration API is called, not as dependencies get chased.

ifdef HCP_CACHE

ifndef HCP_CACHE_READONLY
$(if $(wildcard $(HCP_CACHE)),,$(shell mkdir -p $(HCP_CACHE)))
endif

# $1 - uppercase name for the cache sub-directory
# On return, the HCP_CACHE_DIR_$1 symbol will point to the cache (sub)directory
define cache_add_dir
$(eval upper_parent := $(strip $1))
$(eval lower_parent := $(shell echo "$(upper_parent)" | tr '[:upper:]' '[:lower:]'))
$(eval cache_dir=$(HCP_CACHE)/$(lower_parent))
$(if $(or $(HCP_CACHE_READONLY),$(wildcard $(cache_dir))),,$(shell mkdir $(cache_dir)))
$(eval HCP_CACHE_DIR_$1 := $(cache_dir))
endef

# $1 - uppercase name for the cache sub-directory
# $2 - uppercase name for the asset
# $3 - filename for the asset (without path)
# On return;
# - the HCP_CACHE_FNAME_$2 symbol remembers $3
# - the HCP_CACHE_PATH_$2 symbol will point to the cached file location
# - the HCP_CACHE_HIT_$2 symbol will be set iff the file is in the cache
define cache_add_asset
$(if $(HCP_CACHE),,$(error HCP_CACHE disabled))
$(eval upper_parent := $(strip $1))
$(eval lower_parent := $(shell echo "$(upper_parent)" | tr '[:upper:]' '[:lower:]'))
$(eval upper_asset := $(strip $2))
$(eval lower_asset := $(shell echo "$(upper_asset)" | tr '[:upper:]' '[:lower:]'))
$(eval fname := $(strip $3))
$(eval cache_dir := $(HCP_CACHE)/$(lower_parent))
$(eval cache_path := $(cache_dir)/$(fname))
$(eval HCP_CACHE_FNAME_$(upper_asset) := $(fname))
$(eval HCP_CACHE_PATH_$(upper_asset) := $(cache_path))
$(if $(wildcard $(cache_path)),$(eval cache_hit := 1),$(eval cache_hit :=))
$(eval HCP_CACHE_HIT_$(upper_asset) := $(strip $(cache_hit)))
endef

# $1 - uppercase name for the asset
# $2 - path to (the directory) where the asset file is expected. (The filename
#      is already set in HCP_CACHE_FNAME_$2 from the call to cache_add_dir.)
# On return;
# - if the asset exists in the cache (HCP_CACHE_HIT_$1 is non-empty);
#   - a runtime dependency is created for $2/$fname on the cached file so that
#     it gets copied to $2 when required.
#   - HCP_CACHE_RULE_$1 is set empty, to indicate that the caller should not
#     define rules to download/generate it.
# - if the asset doesn't exist in the cache (HCP_CACHE_HIT_$1 is empty);
#   - if the cache is read-only (HCP_CACHE_READONLY is non-empty);
#     - HCP_CACHE_RULE_$1 is set to $2/$fname, indicating that the caller
#       should define rules to download/generate the file to that path.
#   - if the cache is read-write (HCP_CACHE_READONLY is empty);
#     - HCP_CACHE_RULE_$1 is set to the cache location, indicating that the
#       caller should define rules to download/generate the file to that path.
#     - a runtime dependency is created for $2/$fname on the cached file so
#       that it gets copied to $2 when required.
define cache_consume_asset
$(if $(HCP_CACHE),,$(error HCP_CACHE disabled))
$(eval upper_asset := $(strip $1))
$(eval user_dir := $(strip $2))
$(eval cache_fname := $(HCP_CACHE_FNAME_$(upper_asset)))
$(eval cache_path := $(HCP_CACHE_PATH_$(upper_asset)))
$(eval cache_hit := $(strip $(HCP_CACHE_HIT_$(upper_asset))))
$(if $(cache_hit),
$(eval do_rule := 1)
$(eval user_tgt :=)
,
$(if $(HCP_CACHE_READONLY),
$(eval do_rule :=)
$(eval user_tgt := $(user_dir)/$(cache_fname))
,
$(eval do_rule := 1)
$(eval user_tgt := $(cache_path))
)
)
$(if $(do_rule),
$(user_dir)/$(cache_fname): $(cache_path)
	$Qcp $(cache_path) $(user_dir)/$(cache_fname)
)
$(eval HCP_CACHE_RULE_$(upper_asset) := $(strip $(user_tgt)))
endef

else # !HCP_CACHE

# In the no-cache case, we need to behave the same way we do when the cache is
# enabled but is empty and read-only. That's all these stubs accomplish.
define cache_add_dir
endef
define cache_add_asset
$(eval upper_asset := $(strip $2))
$(eval fname := $(strip $3))
$(eval HCP_CACHE_FNAME_$(upper_asset) := $(fname))
endef
define cache_consume_asset
$(eval upper_asset := $(strip $1))
$(eval user_dir := $(strip $2))
$(eval cache_fname := $(HCP_CACHE_FNAME_$(upper_asset)))
$(eval user_tgt := $(user_dir)/$(cache_fname))
$(eval HCP_CACHE_RULE_$(upper_asset) := $(strip $(user_tgt)))
endef

endif
