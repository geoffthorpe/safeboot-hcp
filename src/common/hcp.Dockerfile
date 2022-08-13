RUN apt-get install -y nginx uuid-runtime
RUN rm /etc/nginx/sites-enabled/default

RUN echo "source /hcp/common/hcp.sh" > /etc/profile.d/hcp_common.sh
RUN echo "source /hcp/common/hcp.sh" > /root/.bashrc
