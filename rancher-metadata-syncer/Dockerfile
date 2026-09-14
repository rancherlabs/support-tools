## Running builder to download metadata files
FROM alpine@sha256:25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659 AS builder
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
FROM httpd:alpine@sha256:1b766f17b84026429b7cb243317b142921b24432336e798bc881c43f45ed9567
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
