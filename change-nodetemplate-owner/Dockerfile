FROM ubuntu
MAINTAINER patrick0057
ENV TERM xterm
RUN apt-get update && apt-get install -y apt-transport-https curl gnupg2 && \
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
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
