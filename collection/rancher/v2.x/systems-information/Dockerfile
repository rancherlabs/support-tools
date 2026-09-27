FROM ubuntu:22.04@sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02
MAINTAINER Rancher Support support@rancher.com
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -yq --no-install-recommends \
curl \
msmtp \
&& apt-get clean && rm -rf /var/lib/apt/lists/*

##Installing kubectl
ARG KUBECTL_VERSION=v1.37.1
# renovate-local: kubectl-amd64=v1.37.1
ARG KUBECTL_SUM_amd64=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8
RUN curl -sSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    echo "${KUBECTL_SUM_amd64}  kubectl" | sha256sum -c - && \
    chmod +x kubectl && \
    mv kubectl /bin/kubectl

ADD *.sh /usr/bin/
RUN chmod +x /usr/bin/*.sh

WORKDIR /root
CMD /usr/bin/run.sh
