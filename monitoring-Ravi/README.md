# Monitoring - ShopNow capstone (Ravi)

This directory installs Prometheus, Grafana and Alertmanager on the existing
EKS cluster using the `kube-prometheus-stack` Helm chart. It is designed for
the temporary capstone demo environment and avoids public monitoring services
and persistent EBS volumes to reduce cost.

## Fixed integration values

- AWS region: `ap-south-1`
- EKS cluster: `shopnow-eks-dev`
- Helm release: `monitoring`
- Kubernetes namespace: `monitoring`
- App namespace assumed by alert rules: `default`
- Required alert file: `monitoring-Ravi/alert-rules.yaml`
- Jenkins metrics path: `/prometheus` on port `8080`
- ShopNow Deployments: `frontend-deployment`, `admin-deployment`, `backend-deployment`

The stack enables the bundled node and Kubernetes dashboards and provisions a
ShopNow application dashboard from `values.yaml`. That dashboard displays
available replicas, container restarts, CPU and memory by pod, and available
replicas by deployment, using Kubernetes metrics from Prometheus. It does not
pretend the ShopNow API itself exposes request-latency metrics; the current app
health route `/api/health` is not a Prometheus metrics endpoint.

## Preconditions

1. The EKS cluster `shopnow-eks-dev` must be active and your current AWS identity
   must have Kubernetes access.
2. `kubectl` must target the intended cluster:

   ```bash
   aws sts get-caller-identity
   aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
   kubectl get nodes
   ```

3. Helm 3 must be installed on the control machine.
4. Coordinate with the team before installing monitoring because it consumes
   CPU and memory on the shared worker nodes.
5. Replace `REPLACE_WITH_JENKINS_HOST_OR_IP:8080` in `values.yaml` with the actual
   Jenkins public DNS name or IP followed by `:8080` before install. Use the
   `jenkins_url` Terraform output to find the endpoint, then remove the `http://`
   prefix and trailing slash for the target value.
6. Jenkins must have the Prometheus metrics endpoint enabled by Kaushik. Because
   the Jenkins server is in a separate VPC from the EKS cluster, Prometheus may
   reach it through the EKS NAT Gateway. Ask Susmitha to confirm that the
   **actual NAT Gateway public IP** is permitted to reach Jenkins port 8080 in
   the Jenkins server security group. Do not open Jenkins to `0.0.0.0/0` just
   to make scraping work. If the team chooses private connectivity instead,
   use that private routable hostname/address.

## Install

Run commands from the capstone repository root. First ensure the namespace
exists, then create a Grafana admin Secret without putting the password in Git.

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
read -s -p 'Grafana admin password: ' GRAFANA_ADMIN_PASSWORD
echo
kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal="admin-password=${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
unset GRAFANA_ADMIN_PASSWORD
```

Add the pinned chart repository and install the stack. Version `92.14.1` is
pinned for repeatable setup; review chart release notes before deliberately
upgrading the version.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 92.14.1 \
  --namespace monitoring \
  --create-namespace \
  --values monitoring-Ravi/values.yaml \
  --wait --timeout 15m
kubectl apply -f monitoring-Ravi/alert-rules.yaml
```

If Jenkins is not ready yet, the Kubernetes stack can still be installed, but
the `jenkins` Prometheus target will remain down until the endpoint and network
access are available. Do not claim that Jenkins scraping is successful until
its target status is `UP`.

## Verify deployment and rules

```bash
helm status monitoring -n monitoring
kubectl get pods -n monitoring
kubectl get prometheus -n monitoring
kubectl get prometheusrules -n monitoring
kubectl get svc -n monitoring
```

Wait until the Prometheus, Grafana, Alertmanager, operator, node-exporter and
kube-state-metrics workloads are Ready. The exact service names are visible in
`kubectl get svc -n monitoring`.

### Open Grafana safely

Grafana is `ClusterIP`; do not make it a public LoadBalancer for this project.
Use port-forwarding from a trusted machine:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Open `http://127.0.0.1:3000`. Username is `admin`; password is the value used
when creating `grafana-admin-credentials`. Check the bundled Kubernetes/node
dashboards and the **ShopNow Application Health** dashboard.

### Check Prometheus and Jenkins target

In a second terminal:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Open `http://127.0.0.1:9090/targets` and confirm the Kubernetes targets and
`jenkins` target. The Jenkins job is configured as `metrics_path: /prometheus`
on port `8080`. A DOWN target usually means the endpoint is disabled, the
hostname/IP is wrong, Jenkins authorization blocks the scrape, or the Jenkins
security group does not allow the EKS NAT egress address.

## Included alert rules

`alert-rules.yaml` creates a `PrometheusRule` named `shopnow-ravi-alerts` for:

- `KubernetesNodeNotReady` - a node remains not Ready for 5 minutes.
- `ShopNowPodCrashLooping` - a pod in the `default` namespace remains in
  `CrashLoopBackOff` for 5 minutes.
- `ShopNowHighContainerCPU` - a ShopNow container averages more than 0.8 CPU
  cores for 10 minutes.
- `ShopNowDeploymentReplicasUnavailable` - an app Deployment has fewer
  available replicas than desired for 5 minutes.

These thresholds are demonstration defaults, not universal production SLOs.
Change `namespace="default"` in the alert expressions if the app manifests use
another namespace. The rule label `release: monitoring` is intentional: it must
match the Helm release name so Prometheus selects the rules.

The rules create alerts in Prometheus/Alertmanager. Email, Slack or other
outbound notifications require a team-approved receiver and secret; no
credentials or unconfirmed notification destination are hard-coded here.
Kaushik remains responsible for Jenkins build/deployment failure notifications.

## Optional controlled crash-loop test

Coordinate with the team before testing in the shared cluster. This deliberately
creates a failing pod in `default`; remove it after the alert has fired.

```bash
kubectl run shopnow-alert-test --namespace default \
  --image=busybox:1.36 --restart=Always \
  --command -- /bin/sh -c 'exit 1'
kubectl get pod shopnow-alert-test -n default -w
```

After the pod remains in `CrashLoopBackOff` long enough for the `for: 5m` rule,
check the Prometheus Alerts page or Alertmanager. Clean up immediately:

```bash
kubectl delete pod shopnow-alert-test -n default
```

## Screenshot checklist

Save genuine evidence in the shared repository `screenshots/` folder. Never
capture Grafana passwords, AWS credentials, cookies or access tokens.

1. `ravi-monitoring-01-helm-release.png` - `helm status monitoring -n monitoring`.
2. `ravi-monitoring-02-pods-ready.png` - monitoring pods running/Ready.
3. `ravi-monitoring-03-prometheus-targets.png` - targets page, including Jenkins `UP` once enabled.
4. `ravi-monitoring-04-node-dashboard.png` - node dashboard with live data.
5. `ravi-monitoring-05-pod-dashboard.png` - pod dashboard with live data.
6. `ravi-monitoring-06-shopnow-dashboard.png` - ShopNow Application Health dashboard.
7. `ravi-monitoring-07-alert-rules.png` - Prometheus rules/alerts page.
8. `ravi-monitoring-08-alert-fired-and-resolved.png` - alert firing and recovery, if you perform the controlled test.

## Cleanup

Coordinate with the team and clean up application resources first. Remove the
custom alert resource, then uninstall the Helm release after evidence is saved:

```bash
kubectl delete -f monitoring-Ravi/alert-rules.yaml
helm uninstall monitoring -n monitoring
kubectl delete secret grafana-admin-credentials -n monitoring
kubectl delete namespace monitoring
```

Only run cleanup when the team is ready; it removes the shared monitoring stack
from the cluster. Prometheus/Grafana history is intentionally ephemeral and is
lost on uninstall because persistence is disabled to control cost.

## Troubleshooting

- **No PrometheusRule / alert absent:** check `kubectl get prometheusrules -n monitoring -o yaml`, ensure `release: monitoring`, and check Prometheus selector settings.
- **Target DOWN:** inspect Prometheus target error text, then verify DNS/IP, Jenkins `/prometheus`, Jenkins authorization and security-group ingress from the NAT Gateway's public IP.
- **No application panels:** check Prometheus has `kube-state-metrics`/kubelet targets up, then verify the actual app namespace and the Deployment names from `kubectl get deploy -A`.
- **Pods Pending or OOMKilled:** inspect `kubectl describe pod -n monitoring <pod>` and `kubectl top nodes`; the cluster is shared and the monitoring resource requests may need review.
- **Grafana dashboard missing:** inspect `kubectl get configmap -n monitoring` and Grafana dashboard sidecar logs; ensure the `grafana.dashboards.default.shopnow-application.json` block remains valid YAML/JSON.
