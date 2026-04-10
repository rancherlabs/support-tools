FROM ubuntu:18.04@sha256:152dc042452c496007f07ca9127571cb9c29697f42acbfad72324b2bb2e43c98
MAINTAINER Rancher Support support@rancher.com
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -yq --no-install-recommends \
curl \
msmtp \
&& apt-get clean && rm -rf /var/lib/apt/lists/*

##Installing kubectl
ARG KUBECTL_VERSION=v1.35.3
# renovate-local: kubectl-amd64=v1.35.3
ARG KUBECTL_SUM_amd64=fd31c7d7129260e608f6faf92d5984c3267ad0b5ead3bced2fe125686e286ad6
RUN curl -sSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    echo "${KUBECTL_SUM_amd64}  kubectl" | sha256sum -c - && \
    chmod +x kubectl && \
    mv kubectl /bin/kubectl

ADD *.sh /usr/bin/
RUN chmod +x /usr/bin/*.sh

WORKDIR /root
CMD /usr/bin/run.sh
