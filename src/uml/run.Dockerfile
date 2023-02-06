# TODO: when we learn how to pass build-args down, the image we copy from will
# be properly parameterised. The hard-coding below is frail.
COPY /start.sh /start.sh
COPY --from=hcp_uml_builder:devel /linux /linux
COPY --from=hcp_uml_builder:devel /lib/modules /lib/modules
RUN chmod 755 /start.sh /linux
