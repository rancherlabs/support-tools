# Description
This script will assist with testing ports for your Rancher installation.  It needs to be run on the receiving end as well as the sending end.  It works by sending a packet with the port number and if the receives that, it will make note of it.  Then when you are ready, you can check the results and it will tell you all of the ports that failed.

# Known Issues
Unfortunately with UDP testing, it can only test the first packet it receives.  If something else hits that port before the script's test packet, it will report a false positive as it stops listening after receiving the first packet.  You also need to make sure you shutdown any services that are using both TCP and UDP ports that you would like to test, otherwise the script will report a false positive since it can't bind to those ports.

# Dependencies
* Netcat BSD version (usually just a yum or apt install)
* pgrep

# Steps

## Download
```
curl -LO https://github.com/patrick0057/porttest/raw/master/porttest.sh
```
or
```
wget https://github.com/patrick0057/porttest/raw/master/porttest.sh
```

## Spawn netcat processes (listen mode)
This should be run on the receiving node that you want to test inbound ports on.
```
bash porttest.sh -l
```

## Send packets
Default ports reference:
* TCP_PORTS="80 443 22 2379 6443 2376 2380 3389 9099 10250 10254 30000"
* UDP_PORTS="8472 30000"

Send packets to default ports
```
bash porttest.sh -s <IP>
```

Send packets to custom ports
```
bash porttest.sh -t 80 443 -u 8473 8888 -s <IP>
```

## Print results
This only needs to be run on the receiving node.
```
bash porttest.sh -r
```

## Cleanup and kill netcat processes
This only needs to be run on the receiving node.
```
bash porttest.sh -kc
```
