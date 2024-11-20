# Rancher Supportability Review Collection Details

## Overview
This document provides transparency about the data collected during a Rancher supportability review. The collection is designed to gather necessary diagnostic information while respecting privacy and security concerns.

## Cluster-Level Collection

### Kubernetes Components
- API server configuration
- Controller manager settings
- Scheduler configuration
- etcd status and metrics
- Kubelet configuration
- Container runtime status

### Workload Information
- Pod status and configuration
- Deployment configurations
- StatefulSet configurations
- DaemonSet configurations
- Service configurations
- Ingress configurations

### Cluster Resources
- Namespace listing
- Resource quotas
- Limit ranges
- Network policies
- Storage classes and PV/PVC status

### Custom Resources
- Rancher-specific CRDs status
- Cluster configuration CRs
- Helm releases

## Node-Level Collection

### System Information
- OS version and distribution
- Kernel parameters
- System resources (CPU, memory, disk)
- Network configuration

### Container Runtime
- Docker/containerd version
- Runtime configuration
- Container logs
- Image list

### Kubernetes Components
- Kubelet status
- Proxy configuration
- CNI configuration
- Container runtime logs

### System Logs
- Kubernetes component logs
- System service logs related to container runtime
- Kernel logs related to container operations

## What is NOT Collected

### Excluded Data
- Application data and logs
- Secrets and sensitive configurations
- User data
- Database contents
- Custom application configurations
- SSL private keys
- Authentication tokens
- Password hashes

### Storage
- Application persistent volumes content
- User uploaded files
- Backup files

### Network
- Raw network traffic
- Packet captures
- Private network configurations
- VPN configurations

## Data Handling

### Collection Process
1. Data is collected using Sonobuoy plugins
2. Information is aggregated at cluster level
3. Results are bundled into a single archive

### Security Measures
- All collection is read-only
- No modifications are made to cluster configuration
- Collection runs with minimal required permissions
- Data transfer is encrypted
- Generated bundles are encoded and compressed

## Usage of Collected Data

The collected information is used for:
- Identifying potential system issues
- Validating configurations
- Ensuring compliance with best practices
- Troubleshooting reported problems
- Providing optimization recommendations

The data is analyzed by SUSE Rancher Support to:
- Verify system health
- Identify potential improvements
- Ensure security compliance
- Provide targeted recommendations
- Support issue resolution

## Questions or Concerns

If you have questions about data collection or need to exclude certain types of information, please contact SUSE Rancher Support before running the collection tool. We can provide guidance on:
- Customizing collection scope
- Excluding sensitive namespaces
- Modifying collection parameters
- Reviewing collection results