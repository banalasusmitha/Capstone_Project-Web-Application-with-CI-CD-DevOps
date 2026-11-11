# CI/CD pipeline guide

How the ShopNow pipelines work, stage by stage, and how they map to the
project brief. Setup is in `setup-guide.md`; fixes in `troubleshooting.md`.

---

## The big picture

```
                 ┌───────────────────────── Jenkins server (EC2, IAM role) ─────────────────────────┐
                 │                                                                                    │
 manual run ───► │ 1-infra-terraform ──apply──► 2-config-ansible ──► 3-app-cicd ◄── git push (webhook │
 (plan/apply/    │  Terraform: VPC, EKS,        Ansible: configure     build → test → push      / poll)│
  destroy)       │  CI agent, S3 state          the CI agent EC2       → deploy → smoke test          │
                 └──────────┬───────────────────────────┬──────────────────────┬────────────────────┘
                            ▼                           ▼                      ▼
                  S3 state + EKS cluster        CI agent EC2           ECR images → EKS pods
                                                                        ▲
                                     Prometheus/Grafana scrape Jenkins ─┘ and the cluster (Ravi)
```

| Brief's pipeline stage | Where it happens |
|---|---|
| 1. Build stage - on push, build images, push to ECR | `3-app-cicd`: Checkout → Build images → Push to ECR |
| 2. Infrastructure provisioning - Terraform, S3 state | `1-infra-terraform` |
| 3. Configuration management - Ansible | `2-config-ansible`, triggered by stage 2 |
| 4. Deployment - manifests, load balancing, scaling, health checks | `3-app-cicd`: Deploy to EKS (Avinash's manifests: Ingress, HPA, probes) |
| 5. Testing & monitoring | `3-app-cicd`: unit, container and smoke tests; Ravi's Prometheus/Grafana scrape Jenkins and the cluster |

**Why three jobs and not one?** Infrastructure changes rarely and takes ~20
minutes; the app changes on every push and takes ~8. Re-running Terraform on
every commit would be slow and risky. The jobs are still chained: a fresh
`apply` runs Ansible, which then deploys the app, so one click brings up the
whole environment (Sprint 6: "build triggers deploy").

**Security.** No AWS access key exists anywhere. The Jenkins EC2 gets
short-lived credentials from its instance profile, and EKS gives that role
cluster-admin through an Access Entry. The only stored secret is the CI
agent's SSH key (credential `ci-agent-ssh`).

---

## Job 1: `1-infra-terraform` (Sprint 2)

Parameter `ACTION`: `plan` (default, safe) / `apply` / `destroy`.

| Stage | What it does | Why |
|---|---|---|
| Checkout | Pulls the capstone repo | Terraform code lives in `terraform-Sushmita/` |
| Preflight | Tool versions; `aws sts get-caller-identity`; **fails if not account 095355901688** | Stops Terraform creating a second, billed environment in the wrong account |
| Terraform Init | `init -backend-config=backend.hcl` | Remote state in S3 with locking - several people and Jenkins share one state |
| Format & Validate | `validate` (blocking), `fmt -check` (warning) | Catches syntax errors before planning |
| Terraform Plan | `plan -out=tfplan` (`-destroy` for destroy); summary shown on the build page; `tfplan.txt` archived | What is applied is exactly what was reviewed |
| Approval | `apply`: click **Apply**. `destroy`: type the cluster name | Nothing changes without a human; destroy can't happen by accident |
| Pre-destroy cleanup | Uninstalls Helm releases, deletes Ingresses, LoadBalancer Services, StatefulSets and PVCs | AWS load balancers and EBS volumes made by Kubernetes are not in Terraform state; left behind they block the VPC delete and keep billing |
| Apply / Destroy | `terraform apply tfplan` | |
| Connect to cluster | `update-kubeconfig`, wait for nodes Ready, apply the gp3 StorageClass, show outputs | Proves the cluster works; MongoDB's PVC needs the StorageClass |
| Trigger Ansible job | Starts `2-config-ansible` and waits for it | Brief, Sprint 3: "Ansible job triggered after the Terraform job completes" |

The binary `tfplan` file is deleted after every run (it can contain secrets);
only the readable `tfplan.txt` is kept.

---

## Job 2: `2-config-ansible` (Sprint 3)

| Stage | What it does |
|---|---|
| Preflight | Fails clearly if `ansible-Ravi/site.yml` is not merged yet; `--syntax-check` |
| Find CI agent | Reads `ci_agent_public_ip` from Terraform state (no hard-coded IPs - they change every rebuild) |
| Build inventory | Uses Ravi's `inventory/aws_ec2.yml` (dynamic, tag `Role=ci_agent`) if present, otherwise a static inventory from the Terraform output; waits for SSH |
| Run playbook | `ansible-playbook` with the `ci-agent-ssh` credential |
| Verify configuration | `docker`, `kubectl`, `git`, `aws` versions and Docker running, on the agent |
| Idempotency check | Runs the playbook again; fails if anything still changes (`changed=0` expected) |
| Trigger app deployment | Starts `3-app-cicd` when called from the infra job |

---

## Job 3: `3-app-cicd` (Sprint 4) - the main pipeline

**Triggers:** GitHub push webhook on the capstone repo *and* the `shopNow`
app repo (both are checked out, so both are watched), plus polling every
5 minutes as a fallback.

| Stage | What it does | Fails the build when |
|---|---|---|
| Checkout | Capstone repo (manifests, tests) + `shopNow` into `app/` | |
| Preflight | Tool versions, account check, works out the ECR registry | wrong account |
| Static checks & unit tests (parallel) | **Backend:** `npm ci` + `node --check` inside `node:18-alpine`; `npm audit` (warning). **Dockerfile lint:** hadolint (warning). **Manifest check:** the three Deployments exist; warns if probes / HPA / Ingress are missing | dependencies don't install, syntax error, a Deployment is missing |
| Build images | `docker build` backend, frontend, admin. Tag `<BUILD_NUMBER>` and `latest`. Frontend/admin get `--build-arg USER_NAME=avinash` | build error |
| Container tests | `jenkins-Kaushik/tests/container-test.sh`: runs all three images together on a Docker network and checks health endpoints, that the React bundles were built for `/avinash` and `/avinash-admin`, that the frontend proxies `/api` to the backend, and that the backend is non-root | any check fails - **nothing broken reaches ECR** |
| Push to ECR | Login with the instance role, push both tags | |
| Deploy to EKS | kubeconfig; gp3 StorageClass; installs ingress-nginx with Helm if the manifests have an Ingress; copies `kubernetes-Avinash/` and rewrites every ECR image to this build's tag; `kubectl apply --dry-run=server`, then `apply`; waits for every Deployment/StatefulSet rollout | dry-run rejects a manifest, or a rollout doesn't finish in 5 min → **automatic `kubectl rollout undo`** and diagnostics (describe, events) in the log |
| Smoke tests | `jenkins-Kaushik/tests/smoke-test.sh`: from a curl pod inside the cluster, backend `/api/health`, `/api/products` (proves MongoDB), frontend and admin `/health`; then from outside through the load balancer, `/avinash/`, `/avinash-admin/`, `/avinash/api/health` | in-cluster check fails → **FAILED**; only external fails → **UNSTABLE** |
| post | Archives rendered manifests and test logs; email on failure/unstable; prunes old images | |

**Why tag with the build number?** Kubernetes only rolls out when the image
reference changes. Re-pushing `v1` or `latest` would leave old pods running.
A unique tag also tells you exactly which build is live (`kubectl describe`),
and makes rollback a one-liner.

**Rollback by hand:**
```bash
kubectl rollout history deployment/frontend-deployment
kubectl rollout undo deployment/frontend-deployment            # previous version
kubectl rollout undo deployment/frontend-deployment --to-revision=3
```

**Where the app is:** the build description and the smoke-test log show
`APP_URL=http://<load balancer>/avinash/`.

---

## Monitoring integration (Sprint 5, with Ravi)

Jenkins exposes metrics at `http://<jenkins ip>:8080/prometheus/` (Prometheus
metrics plugin, installed by the setup script).

**Scrape job** for Ravi's `kube-prometheus-stack` values:

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: jenkins
        metrics_path: /prometheus/
        static_configs:
          - targets: ["<jenkins public ip>:8080"]
```

Prometheus runs in the private subnets, so its requests reach Jenkins from the
cluster's **NAT gateway IP**. Add that IP as `/32` to `webhook_cidrs` in
`terraform-Sushmita/jenkins/terraform.tfvars` (Susmitha). Find it with:
`aws ec2 describe-nat-gateways --query 'NatGateways[0].NatGatewayAddresses[0].PublicIp'`.

**Alert rules** that cover the brief's "Jenkins notifications for failed
deployments":

```yaml
- alert: JenkinsDeployFailed
  expr: default_jenkins_builds_last_build_result_ordinal{jenkins_job="shopnow/3-app-cicd"} == 2
  for: 1m
  labels: { severity: critical }
  annotations:
    summary: "ShopNow deployment pipeline failed"
- alert: JenkinsDown
  expr: up{job="jenkins"} == 0
  for: 2m
  labels: { severity: critical }
```

(`last_build_result_ordinal`: 0 success, 1 unstable, 2 failure, 4 aborted.)

Useful Grafana panels: build duration
(`default_jenkins_builds_last_build_duration_milliseconds`), success/failure
counts, executor usage (`default_jenkins_executors_busy`), queue length.
