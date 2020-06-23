FROM ubuntu:18.04
MAINTAINER Rancher Support support@rancher.com
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -yq --no-install-recommends \
curl \
msmtp \
&& apt-get clean && rm -rf /var/lib/apt/lists/*

##Installing kubectl
RUN curl -k -LO https://storage.googleapis.com/kubernetes-release/release/`curl -k -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl && mv kubectl /bin/kubectl && chmod +x /bin/kubectl

ADD *.sh /usr/bin/
RUN chmod +x /usr/bin/*.sh

WORKDIR /root
CMD /usr/bin/run.sh
