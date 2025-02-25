#!/bin/bash

DNS_TEST=false
NAMESPACE=default

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dns-test)
      DNS_TEST=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "=> Start network overlay and DNS test"
if $DNS_TEST
  then
    DNS_PASS=0; DNS_FAIL=0
  else
    echo "DNS tests are skipped. Use --dns-check to enable."
fi
echo
NET_PASS=0; NET_FAIL=0

while read spod shost sip
do
  echo "Testing pod $spod on node $shost with IP $sip"

  # Overlay network test
  echo "  => Testing overlay network connectivity"
    while read tip thost
  do
    if [[ ! $shost == $thost ]]; then
      kubectl -n $NAMESPACE exec $spod -c overlaytest -- /bin/sh -c "ping -c2 $tip > /dev/null 2>&1"
      RC=$?
      if [ $RC -ne 0 ]; then
        ((NET_FAIL+=1)); echo "    FAIL: $spod on $shost cannot reach pod IP $tip on $thost"
      else
        ((NET_PASS+=1)); echo "    PASS: $spod on $shost can reach pod IP $tip on $thost"
      fi
    fi
  done < <(kubectl get pods -n $NAMESPACE -l name=overlaytest -o jsonpath='{range .items[*]}{@.status.podIP}{" "}{@.spec.nodeName}{"\n"}{end}' | sort -k2)

  if $DNS_TEST; then
    # Internal DNS test
    echo "  => Testing DNS"
    kubectl -n $NAMESPACE exec $spod -c overlaytest -- /bin/sh -c "nslookup kubernetes.default > /dev/null 2>&1"
    RC=$?
    if [ $RC -ne 0 ]; then
      ((DNS_FAIL+=1)); echo "    FAIL: $spod cannot resolve internal DNS for 'kubernetes.default'"
    else
      ((DNS_PASS+=1)); echo "    PASS: $spod can resolve internal DNS for 'kubernetes.default'"
    fi

    # External DNS test
    kubectl -n $NAMESPACE exec $spod -c overlaytest -- /bin/sh -c "nslookup rancher.com > /dev/null 2>&1"
    RC=$?
    if [ $RC -ne 0 ]; then
      ((DNS_FAIL+=1)); echo "    FAIL: $spod cannot resolve external DNS for 'rancher.com'"
    else
      ((DNS_PASS+=1)); echo "    PASS: $spod can resolve external DNS for 'rancher.com'"
    fi
  fi
  echo

done < <(kubectl get pods -n $NAMESPACE -l name=overlaytest -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.nodeName}{" "}{@.status.podIP}{"\n"}{end}' | sort -k2)

NET_TOTAL=$(($NET_PASS + $NET_FAIL))
echo "=> Network [$NET_PASS / $NET_TOTAL]"
if $DNS_TEST; then
  DNS_TOTAL=$(($DNS_PASS + $DNS_FAIL))
  echo "=> DNS     [$DNS_PASS / $DNS_TOTAL]"
fi
echo; echo "=> End network overlay and DNS test"