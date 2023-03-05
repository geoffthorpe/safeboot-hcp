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

# Create all the HCP-expected accounts by baking them into the container image.
# TODO: there should be a JSON file to summarize the uid/gid mappings that get
# created by the following. So that, later on, if a different version or
# configuration creates container (and VM) images that have different uids and
# gids baked into them, a divergence between the JSON summaries would warn of
# what's to come (and even allow a thing to do a thing to upgrade ownerships in
# a directory tree from one JSON uid/gid mapping to another).
RUN adduser --disabled-password --quiet --gecos "Attestsvc DB role,,,," auser
RUN adduser --disabled-password --quiet --gecos "Attestsvc Flask role,,,," ahcpflask
RUN adduser --disabled-password --quiet --gecos "Enrollsvc DB role,,,," emgmtdb
RUN adduser --disabled-password --quiet --gecos "Enrollsvc Flask role,,,," emgmtflask
RUN adduser --disabled-password --quiet --gecos "For remote logins,,,," luser
RUN adduser --disabled-password --quiet --gecos "Alicia Not-Alice,,,," alicia
RUN adduser --disabled-password --quiet --gecos "Test User 1,,,," user1
RUN adduser --disabled-password --quiet --gecos "Test User 2,,,," user2
RUN adduser --disabled-password --quiet --gecos "Test User 3,,,," user3

# Set the launcher as our entrypoint
ENTRYPOINT ["/hcp/common/launcher.py"]
