# Node become NotReady and got "use of closed network connection" in kubelet logs
This script is designed to workaround a upstream bug in kubelet. The issue is in the golang http2 library, that will close the TCP connection that is underlying an http2 ClientConn (maybe there are race conditions in goroutines, etc.). When kubelet is sending a new request, by the convention of http2, it will prefer to use a "CachedConn", so it looks for a ClientConn from ClientConnPool. Sadly, it picked a ClientConn whose TCP connection was already closed due to a previous bug, and any request will fail immediately with "use of closed network connection".

## Bug
[https://github.com/kubernetes/kubernetes/issues/92164](Kubernetes 92164)

## Script logic
To workaround this script, we need to watch the kubelet logs for the message "use of closed network connection". If it's found, we'll do a `docker restart kubelet`.

## Install
- Create namespace
```
kubectl create ns restart-kubelet
```

- Deploy script as configmap
```
kubectl -n restart-kubelet create configmap script --from-file restart-kubelet.sh
```

- Deploy workload
```
kubectl apply -n restart-kubelet -f workload.yaml
```