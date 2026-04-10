# Troubleshooting Scripts

Scripts support **RKE2** and **k3s**. RKE1 commands are preserved in deprecated sections within each README.

## Contents

| Directory | Description |
|-----------|-------------|
| [rke2-reference/](rke2-reference/README.md) | Quick reference: install, binaries, kubeconfig, crictl, logging |
| [etcd/](etcd/README.md) | etcd health, status, maintenance, and direct key queries |
| [kube-apiserver/](kube-apiserver/) | API server endpoint checks and responsiveness |
| [kube-scheduler/](kube-scheduler/) | Find the active kube-scheduler leader |
| [determine-leader/](determine-leader/) | Find the active Rancher leader pod |

## Quick links

- etcd health check script (RKE2/k3s, auto-detecting):
  ```bash
  curl -s https://raw.githubusercontent.com/rancherlabs/support-tools/master/troubleshooting-scripts/etcd/check-endpoints.sh | sudo bash
  ```

- kube-scheduler leader:
  ```bash
  curl -s https://raw.githubusercontent.com/rancherlabs/support-tools/master/troubleshooting-scripts/kube-scheduler/find-leader.sh | bash
  ```

- Rancher leader pod:
  ```bash
  curl -s https://raw.githubusercontent.com/rancherlabs/support-tools/master/troubleshooting-scripts/determine-leader/rancher2_determine_leader.sh | bash
  ```
