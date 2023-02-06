# TODO: same note as in src/uml/run.Dockerfile
COPY --from=hcp_uml_builder:devel /myshutdown /myshutdown
COPY init.sh /
RUN chmod 755 /myshutdown /init.sh
