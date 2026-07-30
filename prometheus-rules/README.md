# Prometheus Rules

A collection of production-ready Prometheus alerting rules for the SUSE cloud-native ecosystem.

The goal of this repository is to provide reusable monitoring packages that help identify operational issues before they become outages.

> [!NOTE]
These rules are provided as examples and should be reviewed and tuned for your own environment before use in production.

---

# Rule Philosophy

These alert rules are designed with the following principles:

- Actionable alerts instead of noisy alerts
- Early detection of failure patterns
- Low false-positive rate
- Clear alert descriptions
- Operational runbooks
- Compatibility with Rancher Monitoring / kube-prometheus-stack

The intent is to provide alerts that an operator can immediately investigate rather than informational notifications.

---

# Deployment

Each rule set contains installation instructions specific to that component.

Typically, rules can be deployed by applying the supplied `PrometheusRule` resources:

```bash
kubectl apply -f rules-file.yaml
```

or through Helm/Kustomize depending on your monitoring stack.

---

# Validation

Before deploying new rules, validate them using `promtool`:

```bash
promtool check rules rules-file.yaml
```

For larger rule collections, consider using `promtool` unit tests as part of CI to validate alert behavior before deployment. :contentReference[oaicite:0]{index=0}

---

# Compatibility

These rules are intended for:

- Rancher Monitoring
- kube-prometheus-stack
- Prometheus Operator

Some alerts rely on metrics provided by:

- kube-state-metrics
- node-exporter
- cAdvisor
- etcd metrics
- Kubernetes control plane metrics

If required metrics are unavailable, the corresponding alerts will remain inactive.

---

# Contributing

Contributions are welcome.

When adding a new rule set:

- Follow the existing directory structure.
- Include a dedicated `README.md`.
- Document required metrics.
- Provide alert descriptions.
- Include a runbook whenever practical.
- Validate rules with `promtool`.
- Keep alert names consistent and descriptive.

---

# Disclaimer

These alert rules are provided as examples to assist with monitoring Kubernetes environments.

Every environment is different. Alert thresholds, evaluation periods, and expressions should be reviewed and adjusted based on workload characteristics, operational requirements, and monitoring objectives.

No warranty is provided regarding completeness or suitability for a particular production environment.

---

# License

This repository is licensed under the Apache License 2.0.
