ARG HCP_WEBTOPRDESKTOPBUILD_DNAME

COPY --from=%%BUILDER_DNAME%% /buildout/ /

RUN dpkg -i /xrdp.deb && \
  rm /xrdp.deb

# add local files
COPY files.tar.gz /
RUN cd / && tar zxf files.tar.gz && rm files.tar.gz
