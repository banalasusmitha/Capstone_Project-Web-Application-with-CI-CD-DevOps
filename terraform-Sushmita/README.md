# Terraform - AWS Infrastructure (Susmitha)

Infrastructure-as-Code layer for the ShopNow capstone: VPC, subnets, IGW/NAT,
security groups, ECR repositories, IAM, the EKS cluster, the Jenkins server
and the CI agent - with Terraform state stored remotely in S3.

Everything the other three workstreams need is exposed as a Terraform output.

The application is [banalasusmitha/shopNow](https://github.com/banalasusmitha/shopNow):
three containers (React frontend on :80, React admin on :80, Express API on
:5000) plus MongoDB on :27017 with a persistent volume. See
[`docs/app-integration.md`](docs/app-integration.md) for exactly what the app
needs from this layer - including the app-level bugs that look like
infrastructure failures if you have not seen them before.

---

## Layout

```
terraform-Sushmita/
├── bootstrap/            # Run ONCE: S3 state bucket + DynamoDB lock table
├── jenkins/              # Jenkins server - its own stack, separate from the cluster
├── modules/
│   ├── vpc/              # VPC, subnets, IGW, NAT, route tables, SGs
│   ├── ecr/              # One repo per service + lifecycle policies
│   ├── iam/              # CI-agent role, instance profile, policies
│   ├── eks/              # Control plane, node group, OIDC, add-ons, access entries
│   └── ci-agent/         # Sprint 3: EC2 that Ansible configures
├── envs/
│   └── dev/              # The cluster stack you actually apply
├── extras/               # gp3 StorageClass for the MongoDB PVC
├── TEAM-HANDOFF.md       # what each teammate needs from this layer
└── docs/                 # Runbook, cost notes, guides, viva study guide
```

Modules are reusable; `envs/dev` supplies the values. Adding a `stage` or
`prod` environment later means copying `envs/dev` and changing a tfvars file -
no module code changes.

---

## What gets created

**`jenkins/`** (applied first, destroyed last)

| Resource | Detail |
|---|---|
| Jenkins server | `t3.medium`, Amazon Linux 2023, 30 GiB gp3 (deleted with the instance), default VPC, Elastic IP |
| IAM | `shopnow-jenkins-server-role` (AdministratorAccess) via instance profile - Terraform, ECR and kubectl with no access keys |
| Security group | SSH + 8080 from `admin_cidrs`; 8080 from GitHub's webhook ranges |

**`envs/dev/`**

| Layer | Resources |
|---|---|
| Network | VPC `10.0.0.0/16`, 2 public + 2 private subnets across 2 AZs, Internet Gateway, 1 NAT Gateway, route tables |
| Security | CI-agent SG (SSH from `admin_cidrs` + the Jenkins server's IP, automatic), extra control-plane SG, Prometheus → Jenkins 8080 rule (NAT IP, automatic) |
| Registry | ECR repos `avinash-shopnow/{frontend,admin,backend}` with scan-on-push and lifecycle policies |
| IAM | CI-agent role + instance profile (ECR push, EKS access), EKS cluster role, node role, EBS CSI IRSA role |
| Compute | EKS control plane, **Kubernetes 1.36**, managed node group (2x `m7i-flex.large` on-demand, scales 2-4) |
| Add-ons | vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver (IRSA), metrics-server |
| Access | EKS Access Entries for teammates and the Jenkins server role |
| CI agent | (Sprint 3) `c7i-flex.large` EC2 with key pair, tagged `Role=ci_agent` - the host Ansible configures |

**`bootstrap/`** - S3 state bucket `shopnow-tfstate-095355901688` (versioned,
encrypted, lifecycle) + DynamoDB lock table.

> **Demo day?** Follow [`docs/demo-day-runbook.md`](docs/demo-day-runbook.md):
> everything up, screenshots, everything down, the same day.
>
> **Sprint 3?** [`docs/sprint3-ci-agent.md`](docs/sprint3-ci-agent.md) — the
> Terraform-provisioned EC2 that Ansible configures, step by step.
>
> **Revising for the viva?** Open [`docs/study-guide.html`](docs/study-guide.html)
> in a browser — the architecture in one diagram, plus practice questions.
>
> **Never used Terraform?** [`docs/terraform-from-zero.md`](docs/terraform-from-zero.md),
> then [`docs/concepts-qa.md`](docs/concepts-qa.md) for the questions that
> actually came up.
>
> **New to this code?** Start with
> [`docs/tf-files-explained.md`](docs/tf-files-explained.md) - why the same
> filenames appear in three folders and what each one holds. Then read
> [`docs/code-walkthrough.md`](docs/code-walkthrough.md), which explains every
> non-obvious line and ends with the questions you should be able to answer in
> the viva.

---

## Prerequisites

```bash
aws --version         # v2
terraform -version    # >= 1.10 (S3 native state locking)
aws configure         # region ap-south-1
aws sts get-caller-identity    # Account must be 095355901688
```

Terraform contains no account ID - it creates resources in whichever account
the running machine's credentials belong to. The whole team works in account
`095355901688`. **Anyone on the team can run it**: the state is shared in S3
with locking, so everyone sees and changes the same environment.

---

## Day 1 + Day 2 runbook (Sprint 1)

### 1. Create the remote state backend (once - already done)

```bash
cd bootstrap
terraform init
terraform apply
terraform output
```

Copy `state_bucket_name` and `lock_table_name` into:
- `envs/dev/backend.hcl` and `jenkins/backend.hcl`
- `envs/dev/terraform.tfvars` (`tf_state_bucket`, `tf_lock_table_name`)

### 2. Provision the environment

Jenkins server first, then the cluster - the cluster gives the Jenkins server
access only if it already exists.

```bash
cd ../jenkins
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan

cd ../envs/dev
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

EKS takes roughly 15-20 minutes: control plane first, then the node group.

### 3. Verify

```bash
terraform output

aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
kubectl get nodes
kubectl get pods -n kube-system
```

Two nodes in `Ready` state, and `coredns`, `aws-node`, `kube-proxy`,
`ebs-csi-*` pods running, means the cluster is good.

### 4. Confirm the state really is remote

```bash
aws s3 ls s3://shopnow-tfstate-095355901688/dev/
```

There should be no local `terraform.tfstate` in `envs/dev`.

### 5. Test destroy (Day 2 deliverable)

Follow step 7 of [`docs/demo-day-runbook.md`](docs/demo-day-runbook.md) -
Kubernetes leftovers first, then `envs/dev`, then `jenkins/` - and the
zero-check in step 8. Then re-apply to prove the environment is reproducible.
**Take screenshots before destroying** - see `docs/day1-day2-checklist.md`.

### Tests

```bash
cd envs/dev && terraform test     # 5 tests, mock provider - no AWS calls, no cost
cd ../../jenkins && terraform test
```

---

## Hand-off to the rest of the team

Full detail per person is in [`TEAM-HANDOFF.md`](TEAM-HANDOFF.md).

| Teammate | What they need | Where it comes from |
|----------|---------------|---------------------|
| Kaushik (Jenkins) | `jenkins_url`, `ssh_command`, `public_ip`, `role_arn` | `terraform output` in `jenkins/` |
| Avinash (Docker/K8s) | `ecr_repository_urls`, `cluster_name`, `docker_build_args`, `app_ingress_paths` | `terraform output` in `envs/dev/` |
| Ravi (Ansible/monitoring) | `ci_agent_public_ip`, `ansible_inventory`, `ci_agent_ssh_command` | `terraform output` in `envs/dev/` |

The Jenkins server gets its AWS permissions from an IAM role through its
instance profile, so there are no `aws-access-key-id` / `aws-secret-access-key`
credentials in Jenkins - worth calling out in the viva.

---

## The ECR repositories

The repositories existed before Terraform (Avinash pushed images first). They
were **imported into state**, so Terraform now manages them and applies the
lifecycle policies and scan-on-push. For reference, the import was:

```bash
cd envs/dev
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/frontend"]' avinash-shopnow/frontend
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/admin"]'    avinash-shopnow/admin
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/backend"]'  avinash-shopnow/backend
```

---

## After the cluster is up: one manual step

The EBS CSI driver is installed by Terraform, but EKS ships no default
StorageClass, so MongoDB's PVC would sit `Pending` forever. Apply the one that
ships with this folder (Kaushik's deploy pipeline also does this):

```bash
kubectl apply -f ../../extras/storageclass-gp3.yaml
kubectl get storageclass
```

`metrics-server` is already installed as an add-on, so the HPA and
`kubectl top nodes` work out of the box - no need for the raw manifest the app
README suggests.

## The USER_NAME build arg

`frontend/Dockerfile` and `admin/Dockerfile` bake `ARG USER_NAME` into the
React bundle at build time. It sets the asset path and the API base URL, so it
must match the ingress path. Terraform owns that value as `app_user_name`
(default `avinash`, matching the images already in ECR) and derives the ECR
namespace from it:

```bash
terraform output app_ingress_paths    # {frontend = "/avinash", admin = "/avinash-admin"}
terraform output docker_build_args    # --build-arg USER_NAME=avinash
```

If Jenkins builds without that arg, the app is served at `/aryan` (the upstream
default) and every asset 404s.

---

## Cost

Roughly **$0.55-0.60/hour** with everything up - about $5 for a demo day (see
[`docs/cost-optimization.md`](docs/cost-optimization.md)). Everything is
destroyed the same day; a $50 AWS budget alert catches anything forgotten.
