# Team handoff - infrastructure layer

Infra is provisioned with Terraform in this folder. Read your section.

Region `ap-south-1` · cluster `shopnow-eks-dev`

```bash
aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
```

`Unauthorized`? Send your `aws sts get-caller-identity` ARN to Susmitha.

---

## Rules for everyone

**0. Everyone must be in the same AWS account.**

Terraform has no account ID in the code - it creates resources in whichever
account your credentials belong to. Two people in two accounts means two
separate clusters and two bills, not one shared environment. Images pushed to
one account's ECR can't be pulled by another account's cluster either - it fails
as a confusing `ImagePullBackOff`.

Check which account you are in:

```bash
aws sts get-caller-identity
```

If yours differs from the rest of the team, say so before doing any more work.

1. **Don't create AWS resources by hand.** They get orphaned on destroy and keep billing.
2. **The cluster is destroyed between sessions** (~$0.30/hr). Post in the group chat before you bring it up or tear it down.
3. **Get IDs from `terraform output`**, not screenshots. They change on every rebuild.
4. **Delete LoadBalancer Services before any teardown** - `kubectl delete svc --all --all-namespaces`. They block the VPC delete and keep billing.

---

## Kaushik - Jenkins

**The Jenkins server now comes from Terraform**: `terraform-Sushmita/jenkins/`.
Ask Susmitha to `apply` it when you need it; it's ready in about 3 minutes.
Please don't create EC2 instances by hand. A manual server is invisible to
`terraform destroy` and keeps billing, which is part of how the credits ran
out.

| Output (`terraform output` in `jenkins/`) | For |
|---|---|
| `jenkins_url` | where Jenkins will be, once installed |
| `ssh_command` | SSH in to install Jenkins |
| `role_arn` | the server's IAM role |

- The server is a plain Amazon Linux 2023 machine. **Installing Jenkins and
  plugins is yours** (or Ravi's Ansible playbook).
- Its IAM role has admin rights, so **Terraform, ECR push and the AWS CLI all
  work with no access keys**. Delete `aws-access-key-id` and
  `aws-secret-access-key` from the Jenkinsfile.
- It gets **`kubectl` admin on the cluster automatically**, as long as the
  Jenkins server is built before the cluster.
- Jenkins lives in its own stack so that a `terraform destroy` on the cluster,
  run from Jenkins, never deletes Jenkins itself.

Tag images with `$BUILD_NUMBER`, not `v1`, and build frontend/admin with
`--build-arg USER_NAME=avinash`.

--------|-----|
| `jenkins_instance_profile_name` | attach to the Jenkins EC2 |
| `jenkins_security_group_id` | its security group (22, 8080 open) |
| `public_subnet_ids` | launch it here |
| `ecr_repository_urls` | build and push stages |

**Delete `aws-access-key-id` and `aws-secret-access-key` from the Jenkinsfile.** Attach the instance profile instead - credentials rotate automatically and the CLI, Docker and kubectl all pick them up. Keep only `AWS_DEFAULT_REGION = 'ap-south-1'`.

The role already has: ECR push, EKS describe, state bucket access, and cluster-admin via an EKS Access Entry. No `aws-auth` editing needed.

Tag images with `$BUILD_NUMBER`, not `v1` - Kubernetes won't roll out an unchanged tag.

Frontend and admin builds **must** pass `--build-arg USER_NAME=avinash`.

`allow_jenkins_to_run_terraform = true` is set — it takes effect at the next `terraform apply`.

**Sprint 3 chain:** Terraform job, then Ansible job against the CI agent
(`ci_agent_public_ip`). Store the agent's private key as a Jenkins credential
("SSH Username with private key", user `ec2-user`). The agent carries the
Jenkins IAM role, so builds on it need no AWS keys. Your Jenkins server's
public IP must be in `admin_cidrs` for SSH to reach it.

---

## Avinash - Docker and Kubernetes

Already installed: EBS CSI driver (IRSA), metrics-server, correctly tagged public subnets for the ingress load balancer.

**Run once before deploying MongoDB:**

```bash
kubectl apply -f terraform-Sushmita/extras/storageclass-gp3.yaml
```

Without it the PVC stays `Pending` forever.

**Skip the ECR `imagePullSecret`** the app README mentions. The token expires in 12 hours; the node role already has pull permission.

**Missing from the current manifests:**

- MongoDB StatefulSet, service and PVC - backend can't connect without it
- `MONGODB_URI` on the backend: `mongodb://mongodb-0.mongodb-service:27017/shopnow`
- An Ingress - all three Services are ClusterIP, nothing is reachable externally
- Probes - backend uses `/api/health`, **not** `/health` (that route doesn't exist)
- CPU requests + HPA - the HPA can't scale without requests

**Two app-repo bugs:**

- `admin/nginx/default.conf` has no `/api/` block, only `/admin/`. Admin dashboard renders but shows no data. Add: `location /api/ { proxy_pass http://backend-service:5000/api/; }`
- Confirm the images were built with `--build-arg USER_NAME=avinash`. The default is `aryan`, baked in at build time, and every asset 404s behind the ingress.

Detail: `docs/app-integration.md`

---

## Ravi - Ansible and monitoring

**Sprint 3: your Ansible target is the CI agent** — an EC2 that Terraform builds
for exactly this. Turned on with `create_ci_agent = true`.

| Output | For |
|--------|-----|
| `ci_agent_public_ip` | the host your playbook connects to |
| `ansible_inventory` | a ready-made static inventory line |
| `private_subnet_ids` | where the EKS nodes run |

- Login user `ec2-user`. Python 3 and AWS CLI v2 come with Amazon Linux 2023;
  **Docker and kubectl are for your playbook.**
- Dynamic inventory: the `aws_ec2` plugin can group on tag `Role=ci_agent`.
- SSH needs your IP in `admin_cidrs` — send it to Susmitha (`curl ifconfig.me`).
  The private key comes from her privately, never via git or the group chat.

**Don't aim Ansible at the EKS worker nodes.** The EKS-optimised AMI already
configures Docker, kubelet and the CNI; reconfiguring them fights with EKS.

**Monitoring (Sprint 5):** metrics-server is installed, so `kubectl top` works
now — but it keeps no history and isn't a Prometheus substitute.
`kube-prometheus-stack` gives you Prometheus, Grafana and Alertmanager in one
Helm install.

--------|-----|
| `private_subnet_ids` | where nodes run |
| `node_group_name` | the managed node group |

Both your folders are still empty, and monitoring needs a live cluster - coordinate before starting.

**Nodes have no public IP and no bastion.** Use SSM, not SSH:

```bash
aws ssm start-session --target <instance-id> --region ap-south-1
```

**Don't aim Ansible at the worker nodes.** The EKS-optimised AMI already configures Docker, kubelet and the CNI; reconfiguring fights with EKS. The Jenkins EC2 is the box that actually needs provisioning.

metrics-server is installed, so `kubectl top` works now - but it keeps no history and isn't a Prometheus substitute. `kube-prometheus-stack` gives you Prometheus, Grafana and Alertmanager in one Helm install.

---

## Running the Terraform

**Anyone on the team can run it.** State lives in S3 with locking, so you all
share one environment - that's what the remote backend is for. If two people
apply at the same moment, the second gets "Error acquiring the state lock" and
waits. No corruption.

**Prerequisites:** Terraform >= 1.6, AWS CLI v2, credentials in the **same AWS
account**, and access to the state bucket.

### First time on your machine

```bash
cd terraform-Sushmita/envs/dev
terraform init -backend-config=backend.hcl
```

Do not skip `-backend-config`. Without it Terraform makes a local state file and
you end up building a second, separate copy of everything.

### Day to day

```bash
terraform output    # the IDs you need - changes on every rebuild
terraform plan      # read-only, shows what would change
```

"No changes" from `plan` means the live environment matches the code.

### Bringing the environment up

```bash
terraform plan -out=tfplan
terraform apply tfplan          # 12-15 min, mostly the control plane

aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
kubectl get nodes
kubectl apply -f ../../extras/storageclass-gp3.yaml
```

If the state bucket doesn't exist yet, run `bootstrap/` first and copy its
output into `envs/dev/backend.hcl`.

### Post in the group chat before you destroy

```bash
terraform destroy
```

This deletes the cluster, VPC and ECR repos for **everyone**, not just you.
Delete LoadBalancer Services first (rule 4) or it hangs on the VPC.

### Changing the code

Edit `envs/dev/terraform.tfvars` for values (region, node size, counts).
Commit and push so nobody else's `plan` shows a diff they didn't make.

### Kaushik - from Jenkins in Sprint 2

Same commands, non-interactive:

```groovy
sh 'terraform init -backend-config=backend.hcl -input=false'
sh 'terraform plan -out=tfplan -input=false'
sh 'terraform apply -input=false -auto-approve tfplan'
```

Needs `allow_jenkins_to_run_terraform = true` set and applied first.

---

| Doc | Covers |
|-----|--------|
| `docs/app-integration.md` | what the app needs from the cluster |
| `docs/troubleshooting.md` | likely errors and causes |
| `docs/cost-optimization.md` | cost decisions, teardown checklist |
| `README.md` | provisioning from scratch |
