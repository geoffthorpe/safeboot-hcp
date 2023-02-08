# Minimal set of system tools that we want in all containers. E.g. because
# scripts require their presence (e.g. 'openssl', xxd, ...) or because they
# make the shell experience in the container tolerable (e.g. 'ip', 'ps',
# 'ping', ...)
RUN apt-get install -y openssl xxd procps iproute2 iputils-ping curl wget acl \
	lsof git jq procmail file time sudo dnsutils

RUN mkdir -p /hcp/base
COPY chowner.sh /hcp/base/
RUN chmod 755 /hcp/base/chowner.sh
