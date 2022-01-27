# Troubleshooting Scripts

## kube-scheduler

### Finding the current leader

Command(s): `curl -s https://raw.githubusercontent.com/rancherlabs/support-tools/master/troubleshooting-scripts/kube-scheduler/find-leader.sh | bash`

**Example Output**

```bash
kube-scheduler is the leader on node a1ubk8slabl03
```

## determine-leader

Command(s): `curl -s https://raw.githubusercontent.com/rancherlabs/support-tools/master/troubleshooting-scripts/determine-leader/rancher2_determine_leader.sh | bash`

**Example Output**

```bash
NAME                                    POD-IP         HOST-IP
cattle-cluster-agent-776d795ff8-x77nq   10.42.0.93     10.10.100.83
cattle-node-agent-4bsx6                 10.10.100.83   10.10.100.83
rancher-54d47dc9cf-d4qt9                10.42.0.92     10.10.100.83
rancher-54d47dc9cf-prn4d                10.42.0.90     10.10.100.83
rancher-54d47dc9cf-rsn4g                10.42.0.91     10.10.100.83

rancher-54d47dc9cf-prn4d is the leader in this Rancher instance
```
