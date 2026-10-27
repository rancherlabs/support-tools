## Running builder to download metadata files
FROM alpine:3.24 AS builder
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
FROM httpd:2.4.69-alpine
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
