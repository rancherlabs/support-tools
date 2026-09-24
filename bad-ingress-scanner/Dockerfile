FROM ubuntu:22.04@sha256:829f6df217bcbae2b371026e81711d1a787c61b2967ad09d015063663ebafbf7
MAINTAINER Matthew Mattox <matt.mattox@suse.com>

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -yq --no-install-recommends \
    apt-utils \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

## Install kubectl
ARG KUBECTL_VERSION=v1.37.1
# renovate-local: kubectl-amd64=v1.37.1
ARG KUBECTL_SUM_amd64=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8
RUN curl -sSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    echo "${KUBECTL_SUM_amd64}  kubectl" | sha256sum -c - && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl

COPY *.sh /root/
RUN chmod +x /root/*.sh
CMD /root/run.sh
