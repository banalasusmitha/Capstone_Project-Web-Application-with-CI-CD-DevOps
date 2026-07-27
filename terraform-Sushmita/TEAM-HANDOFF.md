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

| Output | For |
|--------|-----|
| `jenkins_instance_profile_name` | attach to the Jenkins EC2 |
| `jenkins_security_group_id` | its security group (22, 8080 open) |
| `public_subnet_ids` | launch it here |
| `ecr_repository_urls` | build and push stages |

**Delete `aws-access-key-id` and `aws-secret-access-key` from the Jenkinsfile.** Attach the instance profile instead - credentials rotate automatically and the CLI, Docker and kubectl all pick them up. Keep only `AWS_DEFAULT_REGION = 'ap-south-1'`.

The role already has: ECR push, EKS describe, state bucket access, and cluster-admin via an EKS Access Entry. No `aws-auth` editing needed.

Tag images with `$BUILD_NUMBER`, not `v1` - Kubernetes won't roll out an unchanged tag.

Frontend and admin builds **must** pass `--build-arg USER_NAME=avinash`.

When your job starts running Terraform (Sprint 2), ask Susmitha to set `allow_jenkins_to_run_terraform = true` and re-apply.

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

| Output | For |
|--------|-----|
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
