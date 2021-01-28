#!/bin/bash
echo "Starting webserver..."
apachectl start
echo "ok" > /var/www/src/healthz
if [[ ! -z $HTTP_PROXY ]] || [[ ! -z $http_prozy ]] || [[ ! -z $HTTPS_PROXY ]] || [[ ! -z $https_prozy ]]
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
  cp -f /data/*.json /var/www/src/
fi

echo "Starting in static mode"
while true
do
  sleep 10000
done
