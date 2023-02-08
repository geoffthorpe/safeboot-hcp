# Do our best to ensure that any/all shells come up with the environment (and
# functions) set for best UX.
RUN echo "source /hcp/common/hcp.sh" > /etc/profile.d/hcp_common.sh
RUN echo "source /hcp/common/hcp.sh" > /root/.bashrc

# TODO: this is probably no longer needed. I made webapi support co-tenant instances, so the
# presence of an absolute path suggests this is probably detritus.
RUN rm /etc/nginx/sites-enabled/default
