ARG MYTZ
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN apt-get update
RUN apt-get install -y apt-utils
RUN apt-get -y full-upgrade
COPY timezone /etc
RUN chmod 644 /etc/timezone
RUN cd /etc && rm -f localtime && ln -s /usr/share/zoneinfo/$$MYTZ localtime
ARG HCP_APT_PROXY
ARG HCP_APT_MANPAGES
ARG HCP_BASE
ENV HCP_APT_PROXY=$HCP_APT_PROXY
ENV HCP_APT_MANPAGES=$HCP_APT_MANPAGES
ENV HCP_BASE=$HCP_BASE
COPY apt-proxy.sh apt-manpages.sh /
RUN chmod 755 /apt-proxy.sh /apt-manpages.sh && \
	/apt-proxy.sh && /apt-manpages.sh && \
	rm /apt-proxy.sh /apt-manpages.sh
