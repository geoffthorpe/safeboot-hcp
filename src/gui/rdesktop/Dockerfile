ARG HCP_GUIRDESKTOPBUILD_DNAME

COPY --from=%%BUILDER_DNAME%% /buildout/ /

RUN dpkg -i /xrdp.deb && \
  rm /xrdp.deb

# add local files
COPY /root /
