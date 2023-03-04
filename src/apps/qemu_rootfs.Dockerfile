# TODO: same note as in src/uml/run.Dockerfile
COPY --from=hcp_uml_builder:devel /myshutdown /myshutdown

# The hostfs entry in fstab seems to load the '9p' module automatically but not
# the virtio transport that it depends on. Strangely, a second attempt to do
# the mount seems to work. Anyway, this forces things;
RUN echo "9p" > /etc/modules-load.d/hcp.conf
RUN echo "9pnet_virtio" >> /etc/modules-load.d/hcp.conf

# Set up fstab
RUN echo "/dev/sda1 / ext4 defaults 0 1" > /etc/fstab
RUN echo "hcphostfs /hostfs 9p trans=virtio,msize=10485760 0 0" >> /etc/fstab

# Inhibit painfully-slow boot detection of resume
RUN echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume
RUN update-initramfs -u

# Coax systemd into (a) calling our VDE interface 'vde0', and (b) using DHCP
RUN cp /hcp/qemu/10-vde.link /hcp/qemu/25-vde.network /etc/systemd/network/
RUN chmod 644 /etc/systemd/network/10-vde.link /etc/systemd/network/25-vde.network
RUN systemctl enable systemd-networkd

# Add a systemd unit to do our HCP bidding
RUN cp /hcp/qemu/hcp_systemd.service /etc/systemd/system/
RUN chmod 644 /etc/systemd/system/hcp_systemd.service
RUN systemctl enable hcp_systemd.service

RUN echo "root:123456" | chpasswd 
