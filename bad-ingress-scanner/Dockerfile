FROM ubuntu:20.04@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214
MAINTAINER Matthew Mattox <matt.mattox@suse.com>

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -yq --no-install-recommends \
    apt-utils \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

## Install kubectl
ARG KUBECTL_VERSION=v1.35.3
# renovate-local: kubectl-amd64=v1.35.3
ARG KUBECTL_SUM_amd64=fd31c7d7129260e608f6faf92d5984c3267ad0b5ead3bced2fe125686e286ad6
RUN curl -sSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    echo "${KUBECTL_SUM_amd64}  kubectl" | sha256sum -c - && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl

COPY *.sh /root/
RUN chmod +x /root/*.sh
CMD /root/run.sh
