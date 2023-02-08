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
PKGS += json-glib-tools libjson-perl libncurses5-dev \
	python3 python3-yaml python3-netifaces python3-psutil \
	python3-cryptography python3-openssl \
	python3-flask python3-requests uwsgi-plugin-python3 \
	nginx uuid-runtime \
	openssh-server

$(eval $(call pp_add_layer,\
	APPS_BASE,\
	BASE,\
	APPS,\
	$(PKGS),\
	$(HCP_SRC)/apps/base/Dockerfile,\
	$(HCP_SRC)/apps/base/Makefile $(HCP_SRC)/apps/base/Dockerfile,\
	,\
	,\
	))
