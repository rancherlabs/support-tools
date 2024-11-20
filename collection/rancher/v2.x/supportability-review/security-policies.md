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
    source: ghcr.io/rancher/supportability-review
  - mirrors:
    - registry.example.com/sonobuoy
    source: ghcr.io/rancher/mirrored-sonobuoy-sonobuoy
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

#### 2. Host Path Mounting Blocked
```yaml
# Error:
hostPath volumes are not allowed

# Solution:
Modify PSP to allow hostPath volume types for sonobuoy namespace
```

#### 3. Network Policy Blocks
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
