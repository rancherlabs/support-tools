#!/bin/bash

DNS_CHECK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dns-check)
      DNS_CHECK=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "=> Start network overlay, DNS, and API test"

kubectl get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.nodeName}{" "}{@.status.podIP}{"\n"}{end}' | sort -k2 |
while read spod shost sip
do
  echo "Testing pod $spod on node $shost with IP $sip"

  # Overlay network test
  echo "  => Testing overlay network connectivity"
  kubectl get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.status.podIP}{" "}{@.spec.nodeName}{"\n"}{end}' | sort -k2 |
  while read tip thost
  do
    if [[ ! $shost == $thost ]]; then
      kubectl --request-timeout='10s' exec $spod -c overlaytest -- /bin/sh -c "ping -c2 $tip > /dev/null 2>&1"
      RC=$?
      if [ $RC -ne 0 ]; then
        echo "    FAIL: $spod on $shost cannot reach pod IP $tip on $thost"
      else
        echo "    PASS: $spod on $shost can reach pod IP $tip on $thost"
      fi
    fi
  done

  if $DNS_CHECK; then
    # Internal DNS test
    echo "  => Testing internal DNS"
    kubectl --request-timeout='10s' exec $spod -c overlaytest -- /bin/sh -c "nslookup kubernetes.default > /dev/null 2>&1"
    RC=$?
    if [ $RC -ne 0 ]; then
      echo "    FAIL: $spod cannot resolve internal DNS for 'kubernetes.default'"
    else
      echo "    PASS: $spod can resolve internal DNS for 'kubernetes.default'"
    fi

    # External DNS test
    echo "  => Testing external DNS"
    kubectl --request-timeout='10s' exec $spod -c overlaytest -- /bin/sh -c "nslookup rancher.com > /dev/null 2>&1"
    RC=$?
    if [ $RC -ne 0 ]; then
      echo "    FAIL: $spod cannot resolve external DNS for 'rancher.com'"
    else
      echo "    PASS: $spod can resolve external DNS for 'rancher.com'"
    fi
  else
    echo "  => DNS checks are skipped. Use --dns-check to enable."
  fi

done

echo "=> End network overlay, DNS, and API test"
