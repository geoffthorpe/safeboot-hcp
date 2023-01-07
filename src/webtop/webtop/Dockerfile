# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# add local files, including the script to start the window-manager
COPY files.tar.gz /
RUN cd / && tar zxf files.tar.gz && rm files.tar.gz

# Installed desktop packages and link to the chosen window manager
ARG HCP_WEBTOP_PKGS="mate-desktop-environment firefox-esr"
ARG HCP_WEBTOP_CMD="/usr/bin/mate"
RUN apt-get install --no-install-recommends -y $HCP_WEBTOP_PKGS
RUN rm -f /chosen-wm && ln -s $HCP_WEBTOP_CMD /chosen-wm
