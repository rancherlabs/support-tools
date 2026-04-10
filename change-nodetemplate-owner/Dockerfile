FROM ubuntu:20.04@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214
MAINTAINER patrick0057
ENV TERM xterm
ARG K8S_GPG_SUM=3ecc63922b7795eb23fdc449ff9396f9114cb3cf186d6f5b53ad4cc3ebfbb11f
RUN apt-get update && apt-get install -y apt-transport-https curl gnupg2 && \
curl -sSLo /tmp/k8s-apt-key.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg && \
echo "${K8S_GPG_SUM}  /tmp/k8s-apt-key.gpg" | sha256sum -c - && \
apt-key add /tmp/k8s-apt-key.gpg && rm /tmp/k8s-apt-key.gpg && \
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list && \
apt-get update && \
apt-get install -y kubectl jq && \
rm -rf /var/lib/apt/lists/* && \
mkdir /root/.kube/
COPY change-nodetemplate-owner.sh /usr/bin/
WORKDIR /root
RUN chmod +x /usr/bin/change-nodetemplate-owner.sh
ENTRYPOINT ["/usr/bin/change-nodetemplate-owner.sh"]
CMD []
