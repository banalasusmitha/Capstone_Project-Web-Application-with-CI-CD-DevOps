# Terraform - AWS Infrastructure (Susmitha)

Infrastructure-as-Code layer for the ShopNow capstone: VPC, subnets, IGW/NAT,
security groups, ECR repositories, IAM for Jenkins, and the EKS cluster -
with Terraform state stored remotely in S3.

Everything the other three workstreams need is exposed as a Terraform output.

The application is [banalasusmitha/shopNow](https://github.com/banalasusmitha/shopNow):
three containers (React frontend on :80, React admin on :80, Express API on
:5000) plus MongoDB on :27017 with a persistent volume. See
[`docs/app-integration.md`](docs/app-integration.md) for exactly what the app
needs from this layer - including three app-level bugs that will look like
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
│   ├── iam/              # Jenkins role, instance profile, policies
│   ├── eks/              # Control plane, node group, OIDC, add-ons
│   └── ci-agent/         # Sprint 3: EC2 for Ansible to configure
├── envs/
│   └── dev/              # The stack you actually apply
├── extras/               # gp3 StorageClass for the MongoDB PVC
├── TEAM-HANDOFF.md       # what each teammate needs from this layer
└── docs/                 # Sprint guides, walkthroughs, viva study guide, cost notes
```

Modules are reusable; `envs/dev` supplies the values. Adding a `stage` or
`prod` environment later means copying `envs/dev` and changing a tfvars file -
no module code changes.

---

## What gets created

| Layer     | Resources |
|-----------|-----------|
| Network   | VPC `10.0.0.0/16`, 2 public + 2 private subnets across 2 AZs, Internet Gateway, 1 NAT Gateway, route tables |
| Security  | Jenkins SG (22, 8080), extra control-plane SG (443 from Jenkins) |
| Registry  | ECR repos `avinash-shopnow/{frontend,admin,backend}` with scan-on-push and lifecycle policies |
| IAM       | Jenkins role + instance profile (ECR push, EKS access, state bucket), EKS cluster role, node role, EBS CSI IRSA role |
| Compute   | EKS control plane + managed node group (2x t3.medium Spot) |
| Add-ons   | vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver (IRSA), metrics-server |
| Access    | EKS Access Entries for Jenkins and teammates |
| CI agent  | (Sprint 3, opt-in) EC2 with key pair and the Jenkins instance profile — the host Ansible configures |
| State     | S3 bucket (versioned, encrypted, lifecycle) + DynamoDB lock table |

> **Demo day?** Follow [`docs/demo-day-runbook.md`](docs/demo-day-runbook.md):
> everything up, screenshots, everything down, the same day.
>
> **Sprint 3?** [`docs/sprint3-ci-agent.md`](docs/sprint3-ci-agent.md) — the
> Terraform-provisioned EC2 that Ansible configures, step by step.
>
> **Revising for the viva?** Open [`docs/study-guide.html`](docs/study-guide.html)
> in a browser — the architecture in one diagram, plus 30 practice questions.
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
terraform -version    # >= 1.6 (>= 1.10 to use S3 native locking)
aws configure         # region ap-south-1
aws sts get-caller-identity    # note the Account - everything is created here
```

Terraform contains no account ID. It creates resources in whichever account the
running machine's credentials belong to, so **only one person on the team runs
it**. The `968313778667` values in `terraform.tfvars` and `backend.hcl` were
taken from the existing ECR image URLs - replace them if your account differs.

---

## Day 1 + Day 2 runbook

### 1. Create the remote state backend (once)

```bash
cd bootstrap
terraform init
terraform apply
terraform output
```

Copy `state_bucket_name` and `lock_table_name` into:
- `envs/dev/backend.hcl`
- `envs/dev/terraform.tfvars` (`tf_state_bucket`, `tf_lock_table_name`)

### 2. Provision the environment

```bash
cd ../envs/dev
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

EKS takes roughly 12-15 minutes: control plane first, then the node group.

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
aws s3 ls s3://<state-bucket>/dev/
```

There should be no local `terraform.tfstate` in `envs/dev`.

### 5. Test destroy (Day 2 deliverable)

```bash
terraform destroy
```

Then re-apply to prove the environment is reproducible. **Take screenshots
before destroying** - see `docs/day1-day2-checklist.md`.

---

## Hand-off to the rest of the team

Full detail per person is in [`TEAM-HANDOFF.md`](TEAM-HANDOFF.md).

| Teammate | What they need | Where it comes from |
|----------|---------------|---------------------|
| Kaushik (Jenkins) | `jenkins_instance_profile_name`, `jenkins_security_group_id`, `public_subnet_ids` | `terraform output` |
| Avinash (Docker/K8s) | `ecr_repository_urls`, `cluster_name`, `docker_build_args`, `app_ingress_paths` | `terraform output` |
| Ravi (Ansible/monitoring) | `private_subnet_ids`, `node_group_name` | `terraform output` |

Attaching the instance profile to the Jenkins EC2 instance removes the need
for `aws-access-key-id` / `aws-secret-access-key` credentials in the
`Jenkinsfile` - worth calling out in the viva.

---

## The ECR repositories already exist

The Kubernetes manifests reference images that are already pushed, so
`terraform apply` will fail with `RepositoryAlreadyExistsException`. Two options:

**Import them** (preferred - Terraform then manages them):

```bash
cd envs/dev
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/frontend"]' avinash-shopnow/frontend
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/admin"]'    avinash-shopnow/admin
terraform import 'module.ecr[0].aws_ecr_repository.this["avinash-shopnow/backend"]'  avinash-shopnow/backend
```

**Or skip them** - set `create_ecr_repositories = false` in `terraform.tfvars`.

---

## After the cluster is up: one manual step

The EBS CSI driver is installed by Terraform, but EKS ships no default
StorageClass, so MongoDB's PVC would sit `Pending` forever. Apply the one that
ships with this folder:

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

Roughly **$0.30-0.35/hour** while running (see `docs/cost-optimization.md`).
Destroy the stack whenever the team is not actively demoing.
