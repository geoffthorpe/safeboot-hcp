# HCP apps will all (for now) want;
# - HCP: generic code (env, launcher, webapi, attester, purger, ...)
PKGS := hcp-common hcp-xtra hcp-tools
# - HCP: app/service-specific code (enrollsvc, attestsvc, swtpmsvc, ...)
PKGS += hcp-enrollsvc hcp-attestsvc hcp-policysvc hcp-swtpmsvc
# - HCP: other apps/services (kdcsvc, sshsvc, ...)
PKGS += hcp-kdcsvc hcp-sshsvc
# - external packages, possibly locally-built
PKGS += swtpm-tools libtpms0
# - external packages, upstream, primarily for webapi endpoints
UPSTREAM_PKGS := json-glib-tools libjson-perl libncurses5-dev \
	python3 python3-yaml python3-netifaces python3-psutil \
	python3-cryptography python3-openssl \
	python3-flask python3-requests uwsgi-plugin-python3 \
	nginx uuid-runtime \
	openssh-server

# For various reasons, pp_add_layer must prioritize installing locally-built
# packages, before installing upstream packages. Yet the upstream packages
# listed above have no dependencies on our locally-built stuff, and if the
# upstream packages could be installed first, then there would be less churn
# (and downloading) when making local modifications and rebuilding.
$(eval $(call pp_add_layer,\
	APPS_PRE_BASE,\
	BASE,\
	APPS,\
	$(UPSTREAM_PKGS),\
	$(HCP_SRC)/apps/base/Dockerfile,\
	$(HCP_SRC)/apps/base/Makefile $(HCP_SRC)/apps/base/Dockerfile,\
	,\
	))
$(eval $(call pp_add_layer,\
	APPS_BASE,\
	APPS_PRE_BASE,\
	APPS,\
	$(PKGS),\
	,\
	$(HCP_SRC)/apps/base/Makefile,\
	,\
	))
