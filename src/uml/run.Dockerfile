# TODO: same note as in src/apps/base.Dockerfile
COPY /start.sh /start.sh
COPY --from=hcp_uml_builder:devel /linux /linux
COPY --from=hcp_uml_builder:devel /lib/modules /lib/modules
RUN chmod 755 /start.sh /linux
