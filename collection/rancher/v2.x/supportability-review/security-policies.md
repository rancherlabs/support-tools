# Security Policy Configuration Guide

## Overview
This guide provides detailed configuration examples for running the Rancher Supportability Review tool in environments with various security policies.

## Kyverno Policies

### Required Exclusions
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: privilege-policy
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: privilege-escalation
      match:
        any:
        - resources:
            kinds:
              - Pod
      exclude:
        any:
        - resources:
            namespaces:
            - sonobuoy
      validate:
        message: "Privilege escalation is disallowed..."
```

### Common Kyverno Policies Requiring Modification
- Privilege escalation policies
- Container security policies
- Resource quota policies
- Host path mounting policies

## Pod Security Policies

> `PodSecurityPolicy` was deprecated in Kubernetes 1.21 and removed in 1.25.
> On 1.25 and later, use [Pod Security Admission](#pod-security-admission-psa) instead.

### Required Permissions
```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: sonobuoy-psp
spec:
  privileged: true
  allowPrivilegeEscalation: true
  volumes:
    - hostPath
    - configMap
    - emptyDir
  hostNetwork: true
  hostPID: true
  hostIPC: true
  runAsUser:
    rule: RunAsAny
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  fsGroup:
    rule: RunAsAny
```

## Pod Security Admission (PSA)

The data collection pods run privileged containers and mount `hostPath` volumes, so
the namespace used by `sonobuoy` must be admitted at the `privileged` level.

If the namespace you plan to use for running Sonobuoy does not currently exist, no
action is required on your part. The Sonobuoy application will automatically create
the namespace and grant the necessary privileges.

If the namespace you plan to use for running Sonobuoy already exists, you need to
apply labels using the following command:
```shell
$ kubectl label namespace sonobuoy --overwrite \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged
```
Labeling an existing namespace only helps when it is the one passed to
`--sonobuoy-namespace`. A leftover default `sonobuoy` namespace instead fails the
run with `namespace already exists`; delete it rather than labeling it.

Please note that the namespace used for running Sonobuoy will be deleted after
execution.

## Network Policies

### Sonobuoy Aggregator Access
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-sonobuoy
  namespace: sonobuoy
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: sonobuoy
  egress:
  - to:
    - namespaceSelector: {}
```

## Image Pull Policies

### Required Registry Access
```yaml
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: sonobuoy-repo
spec:
  repositoryDigestMirrors:
  - mirrors:
    - registry.example.com/supportability-review
    source: rancher/supportability-review
  - mirrors:
    - registry.example.com/sonobuoy
    source: rancher/mirrored-sonobuoy-sonobuoy
```

## OPA Exempting Namespaces

### Required Exemption
```yaml
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: "gatekeeper-system"
spec:
  match:
    - excludedNamespaces: ["sonobuoy"]
      processes: ["*"]
```


## Troubleshooting Security Policies

### Common Issues and Solutions

#### 1. Privilege Escalation Blocked
```yaml
# Error:
validation error: privileged containers are not allowed

# Solution:
Add namespace exclusion for sonobuoy namespace in your policy
```

#### 2. Pod Security Admission Rejects the Pods
```yaml
# Error:
pods "sonobuoy" is forbidden: violates PodSecurity "restricted:latest":
privileged (container "XXX" must not set securityContext.privileged=true),
allowPrivilegeEscalation != false, restricted volume types

# Solution:
The namespace predates this run and is missing the privileged enforce label.
Delete it, or label it as shown in the Pod Security Admission section
```

Check what the namespace is currently enforcing:
```shell
$ kubectl get namespace sonobuoy -o jsonpath='{.metadata.labels}'
```
If `pod-security.kubernetes.io/enforce` is absent, the cluster default applies.
Note that a `restricted` message here does not implicate the cluster default when
the label is present and set to `privileged` — in that case the rejection comes
from Kyverno, Gatekeeper, or another admission controller replicating the Pod
Security Standards, not from PSA.

#### 3. Host Path Mounting Blocked
```yaml
# Error:
hostPath volumes are not allowed

# Solution:
Modify PSP to allow hostPath volume types for sonobuoy namespace
```

#### 4. Network Policy Blocks
```yaml
# Error:
unable to connect to sonobuoy aggregator

# Solution:
Ensure NetworkPolicy allows pod-to-pod communication in sonobuoy namespace
```

## Best Practices

### Security Policy Configuration
1. Use namespace-specific exclusions
2. Avoid blanket exemptions
3. Monitor policy audit logs
4. Regular policy review

### Deployment Considerations
1. Use dedicated service accounts
2. Implement least-privilege access
3. Regular security audits
4. Documentation of exceptions

## Support
For additional assistance with security policy configuration, contact SUSE Rancher Support with:
1. Current policy configurations
2. Error messages
3. Cluster configuration details
