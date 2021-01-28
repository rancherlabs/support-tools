#!/bin/bash

echo "####################################################################"
echo "Scanning ingress controllers..."
for ingressPod in `kubectl -n ingress-nginx get pods -l app=ingress-nginx -o name | awk -F'/' '{print $2}'`
do
  echo "Pod: $ingressPod"
  kubectl -n ingress-nginx logs "$ingressPod" | grep 'Error obtaining Endpoints for Service' | awk -F '"' '{print $2}' > ./bad-endpoints.list
  kubectl -n ingress-nginx logs "$ingressPod" | grep 'Error getting SSL certificate' | awk -F '"' '{print $2}' > ./bad-certs.list
done
echo "####################################################################"
echo "Sorting and removing duplicates from lists..."
cat ./bad-endpoints.list | sort | uniq > ./bad-endpoints.list2
mv ./bad-endpoints.list2 ./bad-endpoints.list
cat ./bad-certs.list | sort | uniq > ./bad-certs.list2
mv ./bad-certs.list2 ./bad-certs.list

if [[ ! -z `cat ./bad-endpoints.list` ]]
then
  echo "####################################################################"
  echo "Found bad endpoints."
  cat ./bad-endpoints.list
else
  echo "####################################################################"
  echo "No bad endpoints found."
fi

if [[ ! -z `cat ./bad-certs.list` ]]
then
  echo "####################################################################"
  echo "Found bad certs."
  cat ./bad-certs.list
else
  echo "####################################################################"
  echo "No bad endpoints found."
fi
