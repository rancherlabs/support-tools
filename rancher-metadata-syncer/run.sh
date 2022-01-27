#!/bin/bash
echo "Starting webserver..."
apachectl start
echo "ok" > /usr/local/apache2/htdocs/healthz
if [[ ! -z $HTTP_PROXY ]] || [[ ! -z $HTTPS_PROXY ]]
then
  echo "Detected proxy settings."
  echo "Starting downloader..."
  while true
  do
    /usr/local/bin/download.sh
    echo "Sleeping..."
    sleep 6h
  done
fi

if [[ -d /data ]]
then
  echo "Configmap detected, loading json files from Configmap..."
  tar -zvxf v2-5.json.tar.gz -C /usr/local/apache2/htdocs/
  tar -zvxf v2-5.json.tar.gz -C /usr/local/apache2/htdocs/
fi

echo "Starting in static mode"
while true
do
  sleep 10000
done
