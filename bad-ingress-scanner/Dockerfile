FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -yq --no-install-recommends \
    apt-utils \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

## Install kubectl
ARG KUBECTL_VERSION=v1.37.2
# renovate-local: kubectl-amd64=v1.37.2
ARG KUBECTL_SUM_amd64=c04487523e7aa7d1493f7808174c899db93d7a9cf57531420cd76b9bd415f8f4
RUN curl -sSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    echo "${KUBECTL_SUM_amd64}  kubectl" | sha256sum -c - && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl

COPY *.sh /root/
RUN chmod +x /root/*.sh
CMD /root/run.sh
