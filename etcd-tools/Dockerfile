FROM assaflavie/runlike:latest
MAINTAINER Matthew Mattox <matt.mattox@suse.com>

## Adding etcdctl
ENV ETCD_VER=v3.4.14
ENV GOOGLE_URL=https://storage.googleapis.com/etcd
ENV GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
ENV DOWNLOAD_URL=${GOOGLE_URL}
RUN curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-linux-amd64.tar.gz && \
mkdir -p /tmp/etcd-download-test && \
tar -zvxf /tmp/etcd-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1 && \
rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz && \
cp /tmp/etcd-download-test/etcd* /usr/bin/ && \
chmod +x /usr/bin/etcd*
