## Running builder to download metadata files
FROM ubuntu:18.04 AS builder
MAINTAINER Matthew Mattox matt.mattox@suse.com
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -yq --no-install-recommends \
apt-utils \
wget \
&& apt-get clean && rm -rf /var/lib/apt/lists/*
ADD *.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh
WORKDIR /root/
RUN /usr/local/bin/download.sh

## Building webserver
FROM ubuntu:18.04
MAINTAINER Matthew Mattox matt.mattox@suse.com
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -yq --no-install-recommends \
apt-utils \
apache2 \
&& apt-get clean && rm -rf /var/lib/apt/lists/*
RUN a2enmod rewrite expires
RUN echo "ServerName localhost" | tee /etc/apache2/conf-available/servername.conf
RUN a2enconf servername
COPY apache.conf /etc/apache2/sites-available/
RUN a2dissite 000-default
RUN a2ensite apache.conf
RUN ln -sf /proc/self/fd/1 /var/log/apache2/access.log && \
    ln -sf /proc/self/fd/1 /var/log/apache2/error.log
EXPOSE 80
WORKDIR /var/www/src
COPY --from=builder /root/*.json /var/www/src/
COPY --from=builder /usr/local/bin/*.sh /usr/local/bin/
CMD /usr/local/bin/run.sh
