#!/bin/bash
echo "=> Start network overlay test"
  kubectl get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.nodeName}{"\n"}{end}' |
  while read spod shost 
    do kubectl get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.status.podIP}{" "}{@.spec.nodeName}{"\n"}{end}' |
    while read tip thost
      do kubectl --request-timeout='10s' exec $spod -c overlaytest -- /bin/sh -c "ping -c2 $tip > /dev/null 2>&1"
        RC=$?
        if [ $RC -ne 0 ]
          then echo FAIL: $spod on $shost cannot reach pod IP $tip on $thost
          else echo $shost can reach $thost
        fi
    done
  done
echo "=> End network overlay test"