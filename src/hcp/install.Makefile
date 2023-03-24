# This Makefile gets mounted into a builder container when running the
# 'install' rule.

default: install

# We get asked to 'install' in a staging area, caller sets DESTDIR for this.
$(eval DESTDIR := $(strip $(DESTDIR)))
$(if $(DESTDIR),,$(error DESTDIR is not set))

# The installation prefix should be passed in too (by src/hcp/Makefile)
$(eval LOCAL_PREFIX := $(strip $(LOCAL_PREFIX)))
$(if $(LOCAL_PREFIX),,$(error LOCAL_PREFIX is not set))

# Put them both together and you get;
PREFIX ?= $(DESTDIR)$(LOCAL_PREFIX)
MDIRS += $(PREFIX)

# Build up the set of things to install
hcp_TGTS :=

# $1 - unique name
# $2 - subdir
# $3 - chmod
# $4 - shell command (inside subdir) to list files
# If $4 is empty, the default file list is to look for *.py and *.sh files
define hcp_install
$(eval hcp_TGTS += hcp_$1)
$(eval hcp_$1_CHMOD := $3)
$(eval hcp_$1_SRCPATH := $2)
$(eval hcp_$1_DESTPATH := $2)
$(if $4,$(eval cmd := $4),$(eval cmd := ls -1 *.py *.sh 2> /dev/null || true))
$(eval hcp_$1_FILES := $(shell cd $2 && $(cmd)))
endef

$(eval $(call hcp_install,common,common,755,))
$(eval $(call hcp_install,tools,tools,755,))
$(eval $(call hcp_install,xtra,xtra,755,))
$(eval $(call hcp_install,monolith,monolith,755,))
$(eval $(call hcp_install,enrollsvc,enrollsvc,755,))
$(eval $(call hcp_install,enrollsvc_genprogs,enrollsvc/genprogs,755,ls -1))
$(eval $(call hcp_install,attestsvc,attestsvc,755,))
$(eval $(call hcp_install,policysvc,policysvc,755,))
$(eval $(call hcp_install,swtpmsvc,swtpmsvc,755,))
$(eval $(call hcp_install,kdcsvc,kdcsvc,755,))
$(eval $(call hcp_install,sshd,sshd,755,))
$(eval $(call hcp_install,uml,uml,755,))
$(eval $(call hcp_install,qemu,qemu,755,ls -1 *))

define install_tgt
$(eval x := $(strip $1))
$(eval cmd := /bin/true)
$(foreach f,$($x_FILES),
$(if $($x_PRE_CMD),$(eval cmd += && $($x_PRE_CMD)))
$(eval cmd += && install -D -T -m $($x_CHMOD) $($x_SRCPATH)/$f \
	$(PREFIX)/$($x_DESTPATH)/$f))
$(if $($x_POST_CMD),$(eval cmd += && $($x_POST_CMD)))
install_$x: | $(PREFIX)
	$Qecho "[Install] hcp/$x"
	$Q$(cmd)
install: install_$x
endef

$(foreach x,$(hcp_TGTS),$(eval $(call install_tgt,$x)))

$(MDIRS):
	$Qmkdir -p $@
