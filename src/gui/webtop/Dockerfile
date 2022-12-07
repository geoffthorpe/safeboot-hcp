# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# prevent Ubuntu's firefox stub from being installed (on debian this shouldn't
# matter) Note that the "COPY /root /" command seems to implicitly duplicate
# this step, but that's what linuxserver.io:docker-webtop does too, and I'm
# trying to stick to their script as much as possible.
COPY /root/etc/apt/preferences.d/firefox-no-snap /etc/apt/preferences.d/firefox-no-snap

# Installed desktop packages and link to the chosen window manager
ARG HCP_WEBTOP_PKGS="mate-desktop-environment firefox-esr"
ARG HCP_WEBTOP_CMD="/usr/bin/mate"
RUN apt-get install --no-install-recommends -y $HCP_WEBTOP_PKGS
RUN rm -f /chosen-wm && ln -s $HCP_WEBTOP_CMD /chosen-wm

# add local files, including the script to start the window-manager
COPY /root /
