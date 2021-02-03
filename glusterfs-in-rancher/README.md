# GlusterFS-in-Rancher
How to setup GlusterFS for Rancher 2.x

[GlusterFS](http://www.gluster.org) is an open-source scale-out filesystem.
These examples provide information about how to allow containers to use GlusterFS
volumes.

The example assumes that you have already set up a GlusterFS server cluster and
have a working GlusterFS volume ready to use in the containers.

## Prerequisites

- Set up a GlusterFS server cluster
- Create a GlusterFS volume

## Create endpoints

First, create the endpoint and the service to describe the access details of the standalone GlusterFS.

```
apiVersion: v1
kind: Endpoints
metadata:
  name: glusterfs-cluster
subsets:
  - addresses:
      - ip: 172.27.16.19
    ports:
      - port: 1
  - addresses:
      - ip: 172.27.16.20
    ports:
      - port: 1
```
The `addresses` field should be populated with the addresses of each node in the GlusterFS cluster. It is OK to provide any valid value (from 1 to 65535) in the `port` field.

```sh
$ kubectl create -f 01-endpoint.yml
```

You can verify that the endpoints are successfully created by running.

```sh
$ kubectl get endpoints/glusterfs-cluster
NAME                ENDPOINTS
glusterfs-cluster   172.27.16.19:1,172.27.16.20:1
```

## Create Service

We also need to create a service for these endpoints so that they will persist. We will add this service without a selector to tell Kubernetes we want to add its endpoints manually.

```sh
$ kubectl create -f 02-service.yml
```

## Create Persistent Volume

Then reference the endpoint to tell Kubernetes where the GlusterFS cluster is available and the "testvol01" volume name you created in GlusterFS.

```sh
$ kubectl create -f 03-volume.yml
```

## Create Persistent Volume Claim

```sh
$ kubectl create -f 04-pvc.yml
```

The parameters are explained as the followings.

- **endpoints** is the name of the Endpoints object that represents a Gluster cluster configuration. *kubelet* is optimized to avoid mount storm; it will randomly pick one from the endpoints to mount. If this host is unresponsive,
  the next Gluster host in the endpoints is automatically selected.
- **path** is the Glusterfs volume name.
- **readOnly** is the boolean that sets the mount point readOnly or readWrite.
- **selector** is used to tie the PV and PVC together.

## Create Test Pod

Create a pod that has a container using glusterfs volume.

```sh
$ kubectl create -f 05-nginx.yml
```

You can verify that the pod is running:

```sh
$ kubectl get pods -l app=gluster-Nginx
NAME                               READY   STATUS    RESTARTS   AGE
nginx-glusterfs-55d75bdd9d-tgmgz   1/1     Running   0          2m31s
```

You may execute the command `mount` inside the container to see if the
GlusterFS volume is mounted correctly:

```sh
$ kubectl exec nginx-glusterfs-55d75bdd9d-tgmgz -- mount | grep glusterfs
172.27.16.19:glusterfsvol on /mnt type fuse.glusterfs (rw,relatime,user_id=0,group_id=0,default_permissions,allow_other,max_read=131072)
```
