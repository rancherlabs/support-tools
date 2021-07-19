#!/bin/bash

echo "Verifing docker cli access..."
docker info
RC=$?
if [ $RC -ne 0 ]
then
  echo "Failure: Can not access docker cli"
else
  echo "Success: Can access docker cli"
fi

while true
do
  docker logs --since 60s kubelet 2>&1 | grep 'use of closed network connection' > /dev/null
  if [ $RC -ne 0 ]
  then
    echo "Found message, trying to restart kubelet..."
    docker restart kubelet
  fi
  echo "Sleeping..."
  sleep 60
done