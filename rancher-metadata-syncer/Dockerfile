## Running builder to download metadata files
FROM alpine@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS builder
MAINTAINER Matthew Mattox matt.mattox@suse.com
RUN  apk update && apk add --update-cache \
    wget \
    bash \
  && rm -rf /var/cache/apk/*

ADD *.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh
WORKDIR /root/
RUN /usr/local/bin/download.sh

## Building webserver
FROM httpd:alpine@sha256:4e585da9d0125dec36d4500a9f5c5df7b2c0a01f67cb47865a91a4b05bdbec1b
MAINTAINER Matthew Mattox matt.mattox@suse.com
RUN  apk update && apk add --update-cache \
    wget \
    curl \
    bash \
    gzip \
  && rm -rf /var/cache/apk/*

WORKDIR /var/www/localhost
COPY --from=builder /root/*.json /usr/local/apache2/htdocs/
COPY --from=builder /usr/local/bin/*.sh /usr/local/bin/
CMD /usr/local/bin/run.sh
