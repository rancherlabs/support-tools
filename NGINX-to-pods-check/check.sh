#!/bin/bash


usage()
{
cat << EOF
usage: $0 options
OPTIONS:
   -h      Show this message
   -F      Format Default: Table
EOF
}

VERBOSE=
while getopts .h:F:v. OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         F)
             FORMAT=$OPTARG
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

if [[ -z $FORMAT ]]
then
        FORMAT="Table"
fi

if [[ ! "$FORMAT" == "Table" ]] && [[ ! "$FORMAT" == "Inline" ]]
then
	echo "Invalid Option for flag -F"
	exit 1
fi


kubectl get namespace -o custom-columns=NAMESPACE:.metadata.name --no-headers | while read namespace
do
	kubectl get ingress -n "$namespace" -o custom-columns=ingress:.metadata.name --no-headers | while read ingress
	do
		kubectl get ingress $ingress -n $namespace -o yaml | grep 'serviceName: ' | awk '{print $2}' | sort | uniq | while read servicename
		do
			PORT="$(kubectl get endpoints "$servicename" -n "$namespace" -o yaml | grep 'port:' | awk '{print $2}')"
			if [[ "$PORT" == 'port:' ]]
			then
				PORT="80"
			fi
			kubectl get endpoints "$servicename" -n "$namespace" -o yaml | grep '\- ip:' | awk '{print $3}' | while read endpointpodip
			do
				kubectl -n ingress-nginx get pods -l app=ingress-nginx -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP --no-headers | while read ingresspod nodename podip
				do
					PODNAME="$(kubectl get pods -n $namespace -o custom-columns=POD:.metadata.name,IP:.status.podIP --no-headers | grep "$endpointpodip" | awk '{print $1}' | tr -d ' ')"
					if ! kubectl -n ingress-nginx exec $ingresspod -- curl -o /dev/null --connect-timeout 5 -s -q http://${endpointpodip}:${PORT} &> /dev/null
					then
						if [[ "$FORMAT" == "Inline" ]]
						then
							tput setaf 7; echo -n "Checking Pod $PODNAME PodIP $endpointpodip on Port $PORT in endpoint $servicename for ingress $ingress from $ingresspod on node $nodename "; tput setaf 1; echo "NOK"; tput sgr0
						fi
						if [[ "$FORMAT" == "Table" ]]
						then
							echo "####################################################"
							echo "Pod: $PODNAME"
							echo "PodIP: $endpointpodip"
							echo "Port: $PORT"
							echo "Endpoint: $servicename"
							echo "Ingress: $ingress"
							echo "Ingress Pod: $ingresspod"
							echo "Node: $nodename"
							tput setaf 1;echo "Status: Fail!"; tput sgr0
							echo "####################################################"
						fi
					else
						if [[ "$FORMAT" == "Inline" ]]
						then
							tput setaf 7; echo -n "Checking Pod $PODNAME PodIP $endpointpodip on Port $PORT in endpoint $servicename for ingress $ingress from $ingresspod on node $nodename "; tput setaf 2; echo "OK"; tput sgr0
						fi
						if [[ "$FORMAT" == "Table" ]]
                                                then
                                                        echo "####################################################"
                                                        echo "Pod: $PODNAME"
                                                        echo "PodIP: $endpointpodip"
                                                        echo "Port: $PORT"
                                                        echo "Endpoint: $servicename"
                                                        echo "Ingress: $ingress"
                                                        echo "Ingress Pod: $ingresspod"
                                                        echo "Node: $nodename"
                                                        tput setaf 2;echo "Status: Pass!"; tput sgr0
                                                        echo "####################################################"
                                                fi
					fi
				done
			done
		done
	done
done

