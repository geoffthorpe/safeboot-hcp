# Do some gymnastics so that this hcp.Dockerfile can be included for image builds
# that are otherwise unrelated to debian/apt-get etc.
RUN which apt-get >/dev/null 2>&1 && \
	apt-get install -y nginx uuid-runtime && \
	rm /etc/nginx/sites-enabled/default || true

RUN echo "source /hcp/common/hcp.sh" > /etc/profile.d/hcp_common.sh
RUN echo "source /hcp/common/hcp.sh" > /root/.bashrc
