# Do our best to ensure that any/all shells come up with the environment (and
# functions) set for best UX.
RUN echo "source /hcp/common/hcp.sh" > /etc/profile.d/hcp_common.sh
RUN echo "source /hcp/common/hcp.sh" > /root/.bashrc

# TODO: this is probably no longer needed. I made webapi support co-tenant
# instances, so this global path suggests this is probably detritus.
RUN rm /etc/nginx/sites-enabled/default

# TODO: horrendous - convert the uml kernel and modules into an installable
# package, so we don't need to do this. Same problem in src/uml/run.Dockerfile
COPY --from=hcp_uml_builder:devel /linux /linux
COPY --from=hcp_uml_builder:devel /lib/modules /lib/modules
RUN chmod 755 /linux

# Set the launcher as our entrypoint
ENTRYPOINT ["/hcp/common/launcher.py"]
