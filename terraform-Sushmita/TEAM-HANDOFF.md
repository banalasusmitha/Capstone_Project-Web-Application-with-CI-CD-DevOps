# Team handoff - infrastructure layer

Infra is provisioned with Terraform in this folder. Read your section.

Account `095355901688` · region `ap-south-1` · cluster `shopnow-eks-dev` ·
Kubernetes 1.36

```bash
aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
```

**How we work:** push to your own branch and open a PR into `main`; Kaushik
reviews and merges. **Demo day is 30 Oct.** Everything is built, shown,
screenshotted and destroyed the same day - see `docs/demo-day-runbook.md`.

---

## Rules for everyone

1. **Same AWS account.** `aws sts get-caller-identity` must show
   `095355901688`. Terraform creates resources in whichever account your
   credentials belong to, and images in one account's ECR can't be pulled by
   another account's cluster.
2. **Don't create AWS resources by hand.** They're invisible to
   `terraform destroy` and keep billing. A hand-made server and a forgotten
   cluster are how the credits ran out in October.
3. **Nothing stays running.** Everything up costs ~$0.55-0.60/hour (~$14 a
   day if forgotten). Post in the group before you bring anything up or down.
4. **Get IDs from `terraform output`**, not screenshots. They change on every
   rebuild.
5. **Before any teardown, delete what Kubernetes created** - the
   ingress-nginx load balancer and any PVCs (runbook step 7). They block the
   VPC delete and keep billing.
6. **The CI-agent private key never goes in Git or the group chat.** Susmitha
   sends it privately.

---

## Who can get in where

| Access | Allowed | Set in |
|---|---|---|
| Jenkins UI (8080) and SSH | IPs in `admin_cidrs` | `jenkins/terraform.tfvars` |
| GitHub webhook → Jenkins 8080 | GitHub's webhook IP ranges | `jenkins/terraform.tfvars` (`webhook_cidrs`) |
| SSH to the CI agent | IPs in `admin_cidrs` **+ the Jenkins server (automatic)** | `envs/dev/terraform.tfvars` |
| `kubectl` / `helm` on the cluster | IAM users in `team_principal_arns` **+ the Jenkins server role (automatic)** | `envs/dev/terraform.tfvars` |
| Prometheus → Jenkins 8080 | the cluster's NAT IP (automatic) | `envs/dev/main.tf` |

- **Need SSH or the Jenkins UI?** Send Susmitha your IP: `curl ifconfig.me`.
  Home IPs change, so re-check on demo day.
- **`kubectl` says `Unauthorized`?** Send Susmitha your ARN from
  `aws sts get-caller-identity`. No AWS user of your own? SSH into the Jenkins
  server and run `kubectl`/`helm` there - it already has cluster admin.

---

## Kaushik - Jenkins

**The Jenkins server comes from Terraform**: `terraform-Sushmita/jenkins/`,
its own stack, applied first on demo day (~3 minutes).

| Output (`terraform output` in `jenkins/`) | For |
|---|---|
| `jenkins_url` | where Jenkins will be, once installed |
| `ssh_command` | SSH in to run `install-jenkins.sh` |
| `public_ip` | the Elastic IP - also the Prometheus scrape target |
| `role_arn` | the server's IAM role |

- A plain Amazon Linux 2023 machine (`t3.medium`, 30 GiB). Installing Jenkins
  and its tools is yours (`jenkins-Kaushik/server/install-jenkins.sh`).
- **Terraform runs on it with its IAM role** - `shopnow-jenkins-server-role`
  (AdministratorAccess) through the instance profile. No access keys in
  Jenkins. Sprint 2 proof: the infra pipeline prints
  `Running as: ...assumed-role/shopnow-jenkins-server-role/...` - screenshot it.
- `allow_jenkins_to_run_terraform = false` in `envs/dev` is for the CI agent's
  role, not this server. Leave it.
- **`kubectl` admin is automatic**, as long as the Jenkins server exists
  before the cluster is built. If not, re-run `apply` in `envs/dev`.
- **Separate stack on purpose:** a `terraform destroy` of the cluster, run
  from Jenkins, never deletes Jenkins itself. The Jenkins server is destroyed
  last, from Susmitha's laptop.
- **Sprint 3:** Jenkins can SSH into the CI agent automatically - `envs/dev`
  looks up the server's Elastic IP and allows it. Store the private key as
  the credential `ci-agent-ssh` ("SSH Username with private key", user
  `ec2-user`).
- Infra pipeline: `terraform init -backend-config=backend.hcl`. Never run it
  at the same time as someone's laptop apply (the second one waits on the
  state lock).
- Images: tag with the build number, and build frontend/admin with
  `--build-arg USER_NAME=avinash`.

---

## Avinash - Docker and Kubernetes

Already installed by Terraform: EBS CSI driver (IRSA), metrics-server, and
public subnets tagged for the ingress load balancer.

**Run once before deploying MongoDB** (Kaushik's pipeline does this too):

```bash
kubectl apply -f terraform-Sushmita/extras/storageclass-gp3.yaml
```

Without it the PVC stays `Pending` forever.

**Skip the ECR `imagePullSecret`** the app README mentions. The token expires
in 12 hours; the node role already has pull permission.

**Still missing from `kubernetes-Avinash/` on `main`:**

- MongoDB StatefulSet, headless Service and PVC (`gp3`) - the backend can't
  connect without it
- `MONGODB_URI` on the backend: `mongodb://mongodb-0.mongodb-service:27017/shopnow`
- An Ingress (nginx) for `/avinash` and `/avinash-admin` - all three Services
  are ClusterIP, so nothing is reachable from outside
- Probes - the backend uses `/api/health`, **not** `/health` (that route
  doesn't exist)
- CPU/memory requests + HPA - the HPA can't scale without requests

Keep the Deployment/container names and the image paths
(`.../avinash-shopnow/<service>`) as they are - Kaushik's pipeline swaps the
image tag by matching them.

**Two app-repo bugs:**

- `admin/nginx/default.conf` has no `/api/` block, only `/admin/`. The admin
  dashboard renders but shows no data. Add:
  `location /api/ { proxy_pass http://backend-service:5000/api/; }`
- Images must be built with `--build-arg USER_NAME=avinash`. The default is
  `aryan`, baked in at build time, and every asset 404s behind the ingress.

Detail: `docs/app-integration.md`

---

## Ravi - Ansible and monitoring

**Sprint 3: your Ansible target is the CI agent** - an EC2 that Terraform
builds together with the cluster (`create_ci_agent = true`).

| Output (`terraform output` in `envs/dev/`) | For |
|---|---|
| `ci_agent_public_ip` | the host your playbook connects to |
| `ansible_inventory` | a ready-made static inventory line |
| `ci_agent_ssh_command` | SSH in to check by hand |

- Login user `ec2-user`. Amazon Linux 2023 already has Python 3 and AWS CLI
  v2; **Docker, kubectl, git and Java are for your playbook**.
- Kaushik's pipeline runs `ansible-Ravi/site.yml`, preferring the dynamic
  inventory `inventory/aws_ec2.yml` (`aws_ec2` plugin, group on tag
  `Role=ci_agent`).
- SSH from your laptop needs your IP in `admin_cidrs` - send it to Susmitha.
  The private key comes from her privately.
- **Don't aim Ansible at the EKS worker nodes.** The EKS-optimised AMI already
  configures Docker, kubelet and the CNI; reconfiguring them fights with EKS.

**Monitoring (Sprint 5):** metrics-server is installed, so `kubectl top`
works - but it keeps no history and isn't a Prometheus substitute.
`kube-prometheus-stack` gives you Prometheus, Grafana and Alertmanager in one
Helm install.

- Run `helm` from the Jenkins server (SSH in; it has cluster admin), or from
  your laptop if your IAM user ARN is in `team_principal_arns`.
- The Jenkins scrape target is `http://<jenkins public_ip>:8080/prometheus` -
  use the **public** IP from `terraform output public_ip` in `jenkins/`, since
  Jenkins is in a different VPC. The firewall already lets the cluster in on 8080.
- `helm uninstall` it before teardown, especially if Grafana is exposed with a
  LoadBalancer.

---

## Running the Terraform

**Anyone on the team can run it.** State lives in S3 with locking, so you all
share one environment. If two people apply at the same moment, the second
gets "Error acquiring the state lock" and waits. No corruption.

**Prerequisites:** Terraform >= 1.10, AWS CLI v2, credentials for account
`095355901688`.

### Order: Jenkins server first, then the cluster

```bash
cd terraform-Sushmita/jenkins
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan && terraform apply tfplan

cd ../envs/dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan && terraform apply tfplan   # ~20 min
```

Do not skip `-backend-config`. Without it Terraform makes a local state file
and you end up building a second, separate copy of everything.

```bash
terraform output    # the IDs you need - they change on every rebuild
terraform plan      # read-only; "No changes" means live matches the code
```

### Tearing down

Follow **step 7 of `docs/demo-day-runbook.md`**: Kubernetes leftovers first,
then `envs/dev`, then `jenkins/` last, then the zero-check in step 8. Post in
the group first - it deletes the environment for **everyone**.

### Changing the code

Values live in `envs/dev/terraform.tfvars` and `jenkins/terraform.tfvars`.
Change them on a branch and open a PR, so nobody's `plan` shows a diff they
didn't make.

---

| Doc | Covers |
|-----|--------|
| `docs/demo-day-runbook.md` | bring-up, screenshots, teardown, zero-check |
| `docs/cost-optimization.md` | cost per hour, decisions, the October credits incident |
| `docs/troubleshooting.md` | likely errors and causes |
| `docs/app-integration.md` | what the app needs from the cluster |
| `docs/sprint3-ci-agent.md` | the CI agent, step by step |
| `README.md` | the folder layout and what gets created |
