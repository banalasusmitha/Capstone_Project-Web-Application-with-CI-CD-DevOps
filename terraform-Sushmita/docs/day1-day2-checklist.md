# Day 1 + Day 2 - task checklist and evidence

Tick each row once it is done, and drop the screenshot into `../screenshots/`
using the filename in the last column. Documentation is 15% of the grade and
screenshots are what the reviewer actually looks at.

## Day 1

| # | Task | Where it lives | Evidence to capture |
|---|------|----------------|---------------------|
| 1 | Create IAM users/roles | `modules/iam` + `modules/eks` (cluster/node roles) | IAM console showing `shopnow-dev-jenkins-role`, `shopnow-eks-dev-cluster-role`, `shopnow-eks-dev-node-role` → `iam-roles.png` |
| 2 | Create ECR repository | `modules/ecr` | ECR console listing the three repos → `ecr-repos.png` |
| 3 | Create VPC, subnets, IGW, SGs | `modules/vpc` | VPC resource map + subnet list → `vpc-resource-map.png`, `subnets.png` |
| 4 | Set up Terraform project structure | whole folder | `tree terraform-Sushmita` output → `project-structure.png` |

## Day 2

| # | Task | Where it lives | Evidence to capture |
|---|------|----------------|---------------------|
| 5 | Terraform scripts for AWS resources | `modules/*`, `envs/dev` | `terraform validate` + `terraform plan` summary → `terraform-plan.png` |
| 6 | Create EKS cluster | `modules/eks` | `kubectl get nodes` and the EKS console overview → `kubectl-get-nodes.png`, `eks-console.png` |
| 7 | Configure S3 backend | `bootstrap/`, `envs/dev/backend.hcl` | `terraform init` showing "Successfully configured the backend s3" + `aws s3 ls` of the state key → `s3-backend.png` |
| 8 | Test apply and destroy | runbook in `README.md` | Tail of `terraform apply` (Apply complete! N added) and `terraform destroy` (Destroy complete!) → `apply-complete.png`, `destroy-complete.png` |

## After Day 2 - unblocking Avinash

```bash
kubectl apply -f ../../extras/storageclass-gp3.yaml   # MongoDB PVC needs this
kubectl get storageclass
kubectl top nodes                                     # proves metrics-server works
terraform output docker_build_args                    # --build-arg USER_NAME=avinash
```

## Command sequence for the demo

```bash
# Day 1 - state backend
cd bootstrap && terraform init && terraform apply && terraform output

# Day 2 - the environment
cd ../envs/dev
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output

aws eks update-kubeconfig --region ap-south-1 --name shopnow-eks-dev
kubectl get nodes -o wide
kubectl get pods -n kube-system

# Prove reproducibility, then tear down
terraform destroy
```

## Questions you are likely to be asked in the viva

**Why store state in S3 instead of locally?**
Four people work on the same infrastructure. A local state file means only one
person can apply, and losing the laptop loses the record of what exists. S3
gives shared access, versioning for rollback, and encryption at rest. Locking
(S3 lockfile or DynamoDB) stops two people applying at once and corrupting it.

**Why public *and* private subnets?**
Load balancers and the NAT Gateway must be publicly reachable; worker nodes
should not be. Nodes in private subnets reach the internet outbound through
NAT but cannot be reached inbound from it.

**What do the `kubernetes.io/role/elb` subnet tags do?**
They tell the AWS cloud controller which subnets to place internet-facing
load balancers in when the NGINX ingress controller creates a Service of type
LoadBalancer. Without them, provisioning fails with a subnet-discovery error.

**Why modules instead of one big main.tf?**
Reuse and blast radius. `envs/dev` and a future `envs/prod` share identical
module code with different variables, so environments cannot drift.

**What is IRSA and why is it here?**
IAM Roles for Service Accounts. The EBS CSI driver pod assumes an IAM role
through the cluster's OIDC provider instead of inheriting the node's
permissions - so only that pod can create EBS volumes.

**How does Jenkins get permission to push to ECR and deploy to EKS?**
An IAM instance profile on the Jenkins EC2 instance (no stored access keys),
plus an EKS Access Entry mapping that role to `AmazonEKSClusterAdminPolicy`,
which is what authorises `kubectl` against the cluster.

**Why Spot instances?**
60-70% cheaper than On-Demand. The workload is stateless and replicated, and
EKS drains a node gracefully on a Spot interruption notice. MongoDB is the one
stateful component - in production it would go on On-Demand nodes or move to
DocumentDB/Atlas.
