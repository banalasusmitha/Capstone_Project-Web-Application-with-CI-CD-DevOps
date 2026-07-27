# Code walkthrough - what every file does and why

This document exists so you can explain this folder to someone else. Read it
once end to end, then use the "Questions you should be able to answer" section
at the bottom to check yourself before the viva.

---

## 1. The mental model

There are three layers, and they run in order:

```
bootstrap/          run ONCE, by hand, with local state
   creates the S3 bucket where all other state lives
        │
        ▼
envs/dev/           the stack you apply and destroy repeatedly
   reads its state from that S3 bucket
   calls the four modules below
        │
        ▼
modules/vpc  modules/ecr  modules/iam  modules/eks
   reusable building blocks - they contain no hard-coded values
```

**Why the split?** A module is a function; an environment is a call to that
function. `modules/vpc` says *how* to build a VPC. `envs/dev` says *build one
with CIDR 10.0.0.0/16 in ap-south-1*. When you later add `envs/prod`, you copy
one small folder and change a `.tfvars` file - the module code never changes,
so the two environments cannot drift apart.

---

## 2. Terraform concepts used in this code

You will be asked about at least three of these. Learn them from the actual
lines in your own files rather than from a tutorial.

| Concept | What it means | Where to point in the code |
|---------|---------------|----------------------------|
| `resource` | Something Terraform creates and owns | `aws_vpc.this` in `modules/vpc/main.tf` |
| `data` | Something that already exists, which Terraform only reads | `data "aws_availability_zones" "available"` |
| `variable` | An input to a module | every `variables.tf` |
| `output` | A value a module hands back to its caller | every `outputs.tf` |
| `locals` | A computed value used inside one file, not settable from outside | `local.azs`, `local.nat_count` |
| `module` | A call to a folder of reusable code | the four `module` blocks in `envs/dev/main.tf` |
| `count` | Create N copies of a resource, indexed `[0]`, `[1]` | `aws_subnet.public` |
| `for_each` | Create one copy per key in a set or map | `aws_ecr_repository.this` |
| `depends_on` | Force an ordering Terraform cannot infer itself | on `aws_eks_node_group` |
| `lifecycle` | Change how Terraform treats drift | `ignore_changes` on the node group |
| `backend` | Where the state file is stored | `envs/dev/backend.tf` |

**`count` vs `for_each` - the one distinction worth memorising.** `count` gives
you a list indexed by position, so deleting the middle item renumbers everything
after it and Terraform destroys and recreates them. `for_each` gives you a map
keyed by name, so deleting one leaves the others untouched. Subnets use `count`
because they are interchangeable and their order is stable. ECR repos use
`for_each` because removing `admin` must not disturb `frontend` and `backend`.

---

## 3. `bootstrap/` - the chicken-and-egg folder

**The problem it solves.** You want state in S3. But Terraform needs a bucket
before it can write state there, and creating that bucket is itself a Terraform
action that would need somewhere to store *its* state. So this one small stack
deliberately keeps its state in a local file and creates the bucket everything
else uses.

**`bootstrap/main.tf`, resource by resource:**

- `aws_s3_bucket.tf_state` - the bucket. Its name is
  `shopnow-tfstate-<account-id>` because S3 bucket names are globally unique
  across every AWS customer on earth; appending the account ID guarantees no
  collision. `force_destroy = false` means `terraform destroy` will refuse to
  delete it while objects remain. That is deliberate - it protects your state.

- `aws_s3_bucket_versioning` - keeps every previous version of the state file.
  This is your undo button. If an apply is interrupted halfway and writes a
  truncated state, you restore the previous version instead of rebuilding the
  environment from scratch.

- `aws_s3_bucket_server_side_encryption_configuration` - state files contain
  resource IDs, ARNs and sometimes secrets in plain text. Encrypting at rest is
  not optional in any real workplace.

- `aws_s3_bucket_public_access_block` - four separate settings, all `true`,
  that make it impossible to accidentally make this bucket public.

- `aws_s3_bucket_lifecycle_configuration` - versioning means every apply adds a
  new object version forever. This expires non-current versions after 30 days so
  storage does not creep upward.

- `aws_dynamodb_table.tf_lock` - the lock table. When you run `apply`,
  Terraform writes a row here. If a teammate runs `apply` at the same moment,
  their write fails and they get "Error acquiring the state lock" instead of
  both of you corrupting the state. `PAY_PER_REQUEST` billing means it costs
  nothing when idle.

**Why is this in a `count`?** Terraform 1.10 added native S3 locking (a lock
*object* in the bucket instead of a DynamoDB row), so the table is optional.
`create_dynamodb_lock_table` defaults to `true` so the setup works even if a
teammate is on an older Terraform version.

---

## 4. `modules/vpc/` - the network

This is the module worth understanding deepest, because most EKS failures are
actually networking failures.

**The CIDR maths.** You give it `10.0.0.0/16`. It computes subnets itself:

```hcl
public_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
private_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + var.az_count)]
```

`cidrsubnet("10.0.0.0/16", 4, 0)` means *add 4 bits to the /16 prefix, then take
block number 0*, giving `10.0.0.0/20`. Block 1 is `10.0.16.0/20`, and so on.
With `az_count = 2` you get public blocks 0 and 1, private blocks 2 and 3 - no
overlap, and it recalculates correctly if you change `az_count` to 3.

**Why public AND private subnets?** Two different jobs:

- *Public* subnets have a route to the Internet Gateway. Things that must be
  reachable from the internet live here: the load balancer, the NAT Gateway,
  the Jenkins EC2 instance.
- *Private* subnets have no route from the internet. Worker nodes live here, so
  nobody can reach your pods directly. They still reach *outward* (to pull
  images, to call the EKS API) through the NAT Gateway.

**The subnet tags are not decoration.** These lines matter:

```hcl
"kubernetes.io/role/elb"                    = "1"    # on public subnets
"kubernetes.io/role/internal-elb"           = "1"    # on private subnets
"kubernetes.io/cluster/${var.cluster_name}" = "shared"
```

When the NGINX ingress controller creates a `Service` of type `LoadBalancer`,
the AWS cloud controller has to guess which subnets to put the load balancer
in. It does that by looking for exactly these tags. Without them you get a
subnet-discovery error and no load balancer, and it is a genuinely confusing
failure because nothing in Kubernetes mentions tags.

**Internet Gateway vs NAT Gateway - the classic exam question.**

- An **Internet Gateway** is bidirectional. It lets the internet reach your
  resources and your resources reach the internet. It is free.
- A **NAT Gateway** is outbound only. Private resources can start a connection
  out; nothing outside can start a connection in. It costs about $32/month plus
  a per-GB charge.

That is the entire security argument for putting nodes in private subnets.

**The `nat_count` local:**

```hcl
nat_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : var.az_count) : 0
```

A nested ternary that reads: no NAT at all, one shared NAT, or one per AZ.
Most tutorials create one per AZ, which triples the bill for zero benefit in a
dev environment. This is one of your cost-optimisation talking points.

**Route tables.** One shared public route table (all public subnets behave
identically). But one private route table *per AZ*, because if you ever move to
one NAT per AZ, each AZ's traffic must point at its own NAT. Building it that
way now means flipping `single_nat_gateway` to `false` requires no code change.

**Security groups.** Two of them:
- `jenkins` - ports 22 and 8080 from `admin_cidrs`.
- `eks_control_plane_extra` - port 443, and note the ingress rule uses
  `security_groups`, not `cidr_blocks`. That means "allow anything in the
  Jenkins security group", which keeps working when the Jenkins instance is
  replaced and gets a new IP. Referencing a security group instead of an IP
  range is the AWS-native way to express "these two things may talk".

---

## 5. `modules/ecr/` - the image registry

Small module, three ideas.

- `for_each = toset(var.repository_names)` creates one repo per service name.
- `scan_on_push = true` runs a CVE scan on every pushed image. Free, and it is
  a security tick in the marking rubric.
- `aws_ecr_lifecycle_policy` is the cost control. Two rules: expire untagged
  layers after 3 days, and keep only the last 10 images. Without this, every
  Jenkins build adds roughly 300 MB that nothing ever cleans up. Note
  `rulePriority` - ECR evaluates rules in priority order, and a rule with
  `tagStatus = "any"` must come last or it would swallow the untagged rule.

`force_delete = true` lets `terraform destroy` remove a repository that still
contains images. Convenient for a capstone, dangerous in production - say that
out loud if asked.

---

## 6. `modules/iam/` - permissions for Jenkins

**The central idea: no access keys.**

Your current `Jenkinsfile` reads `aws-access-key-id` and
`aws-secret-access-key` from Jenkins credentials. Those are long-lived secrets
sitting on a server. This module creates an **IAM role** plus an **instance
profile**, which you attach to the Jenkins EC2 instance. AWS then hands the
instance temporary credentials that rotate automatically, and there is nothing
to leak.

**How a role is defined - two halves that people mix up:**

- The **trust policy** (`assume_role_policy`) answers *who is allowed to become
  this role*. Here it is the EC2 service.
- The **permissions policy** (`aws_iam_policy.jenkins`) answers *what the role
  can do once assumed*.

**Reading the permissions policy.** Note that `ecr:GetAuthorizationToken` sits
in its own statement with `resources = ["*"]`. That is not laziness - AWS does
not support scoping that particular action to a repository, so it physically
cannot be narrowed. Every other ECR action *is* scoped to your three repository
ARNs. Being able to explain why one statement is wildcarded and the others are
not is exactly the kind of detail that reads as real understanding.

The `dynamic "statement"` block is a loop that emits the DynamoDB statement only
when a lock table name was supplied - because with S3 native locking there is no
table to grant access to.

`allow_jenkins_to_run_terraform` attaches `PowerUserAccess` and defaults to
`false`. In Sprint 2, when Jenkins itself runs `terraform apply`, you flip it to
`true`. Be honest that `PowerUserAccess` is broad; the least-privilege version
would be a hand-written policy covering `ec2:*`, `eks:*`, `ecr:*` and
`iam:PassRole`.

---

## 7. `modules/eks/` - the cluster

The biggest file. Work through it in the order things get created.

**Step 1 - the cluster IAM role.** EKS needs its own role to manage AWS
resources on your behalf (creating ENIs, talking to EC2). Two managed policies
attached: `AmazonEKSClusterPolicy` and `AmazonEKSVPCResourceController`.

**Step 2 - the CloudWatch log group.** Created *before* the cluster, so
retention is set from day one. If EKS creates the group itself, retention
defaults to "never expire" and logs accumulate forever. Only `api` and
`authenticator` log types are enabled; `audit` is the expensive, chatty one.

**Step 3 - `aws_eks_cluster`.** The control plane. Points at
`concat(public_subnet_ids, private_subnet_ids)` so its ENIs can reach both
tiers. `endpoint_private_access` and `endpoint_public_access` are both on -
public so you can run `kubectl` from your laptop, private so in-VPC traffic
never leaves the network.

The `access_config` block is the modern piece:

```hcl
authentication_mode                         = "API_AND_CONFIG_MAP"
bootstrap_cluster_creator_admin_permissions = true
```

Historically, granting someone `kubectl` access meant hand-editing a
ConfigMap called `aws-auth` inside the cluster - fiddly, and a typo locked
everyone out permanently. **EKS Access Entries** replace that with a proper API
you can manage in Terraform. `bootstrap_cluster_creator_admin_permissions`
makes whoever ran `apply` (you) an admin automatically.

**Step 4 - the OIDC provider.** This is the concept most worth learning
properly, because it is the answer to "how does a pod get AWS permissions
without an access key?"

Every EKS cluster publishes an OIDC identity endpoint. Registering it as an IAM
identity provider means IAM will trust tokens the cluster issues. A pod's
service account gets such a token, presents it to STS, and receives temporary
AWS credentials. This is called **IRSA** - IAM Roles for Service Accounts.

Look at the condition in `data.aws_iam_policy_document.ebs_csi_assume`:

```hcl
variable = "${local.oidc_host}:sub"
values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
```

That says: *only* the service account named `ebs-csi-controller-sa` in the
`kube-system` namespace may assume this role. Not any pod, not the node - that
one service account. Without the condition, any pod in the cluster could assume
it. The alternative approach is attaching EBS permissions to the node role,
which would give *every* pod on that node the ability to create and delete EBS
volumes. IRSA is per-pod least privilege.

**Step 5 - the node role.** Four managed policies, and each one has a reason:

| Policy | Why the node needs it |
|--------|-----------------------|
| `AmazonEKSWorkerNodePolicy` | lets the node register itself with the cluster |
| `AmazonEKS_CNI_Policy` | lets the VPC CNI attach ENIs and hand pods real VPC IPs |
| `AmazonEC2ContainerRegistryReadOnly` | lets the kubelet pull your images from ECR |
| `AmazonSSMManagedInstanceCore` | lets you open a shell on a private node without SSH or a bastion |

The first three are mandatory. A node group stuck in `CREATE_FAILED` is very
often one of them missing.

**Step 6 - `aws_eks_node_group`.** The actual EC2 instances.

- `capacity_type = "SPOT"` - spare AWS capacity at 60-70% off, reclaimable with
  a 2-minute warning. Fine here because the app is replicated and stateless.
  Two instance types are listed so EKS can find capacity in either Spot pool.
- `ignore_changes = [scaling_config[0].desired_size]` - once the HPA or the
  autoscaler scales the group to 3 nodes, the real count no longer matches your
  `desired_size = 2`. Without this line, the next `terraform apply` would helpfully
  scale you back down mid-demo. This tells Terraform "I set the initial value,
  something else owns it after that."
- `depends_on` on the policy attachments - Terraform can see that the node group
  needs the *role*, but not that the role needs its *policies* first. Without
  it, nodes occasionally launch a second before they are allowed to join and
  fail. This is the standard example of when `depends_on` is genuinely needed.

**Step 7 - the add-ons.** `vpc-cni`, `kube-proxy` and `coredns` are the cluster
essentials; `aws-ebs-csi-driver` provides persistent volumes for MongoDB;
`metrics-server` feeds the HPA and `kubectl top`. CoreDNS and the CSI driver
carry `depends_on = [aws_eks_node_group.this]` because their pods need a node
to schedule onto - creating them against an empty cluster leaves them Pending
and the apply times out.

**Step 8 - access entries.** One per ARN in `cluster_admin_principal_arns`,
each paired with an `aws_eks_access_policy_association` granting
`AmazonEKSClusterAdminPolicy`. This is how the Jenkins role and your teammates
get `kubectl` access.

---

## 8. `envs/dev/` - where values meet code

**`versions.tf`** pins Terraform and provider versions. The `default_tags` block
on the provider is quietly useful: every resource created by this configuration
gets `Project`, `Environment`, `ManagedBy` and `Owner` tags without you writing
them 40 times. When four people share one AWS account, `Owner = susmitha` is how
you prove which resources are yours.

**`backend.tf` + `backend.hcl`.** The backend block is deliberately empty:

```hcl
terraform {
  backend "s3" {}
}
```

Backend configuration cannot use variables - a hard Terraform limitation,
because the backend must be resolved before variables are evaluated. The
workaround is a separate file passed at init time:

```bash
terraform init -backend-config=backend.hcl
```

Now `envs/prod` can point at a different bucket with no code change.

**`main.tf`** is the wiring. It contains no `resource` blocks at all - only
`locals` and four `module` calls. Two lines are worth understanding:

```hcl
ecr_namespace = coalesce(var.ecr_namespace, "${var.app_user_name}-shopnow")
```

`coalesce` returns the first non-null argument, so this means "use the override
if given, otherwise derive it". That is how one `app_user_name` value drives the
Docker build arg, the ingress path and the ECR namespace at once.

```hcl
node_subnet_ids = var.enable_nat_gateway ? module.vpc.private_subnet_ids : module.vpc.public_subnet_ids
```

This encodes a rule you would otherwise have to remember: with no NAT Gateway,
private subnets have no outbound route, so nodes placed there could never reach
the EKS API and would never join the cluster. Turning off NAT automatically
moves the nodes to public subnets.

**`outputs.tf`** is the contract with your teammates. Everything they need -
ECR URLs, cluster name, the Jenkins instance profile, the ingress paths - comes
out of `terraform output` rather than a WhatsApp message.

**`terraform.tfvars`** is the only file you normally edit. It holds no secrets,
so it is safe to commit, and it is the single place to change region, sizes or
names.

---

## 9. How the dependency graph actually resolves

Terraform does not run top to bottom. It builds a graph from the references
between resources and runs independent branches in parallel. For this stack the
real order is roughly:

```
VPC ──> subnets ──> IGW ──> NAT ──> route tables
  │                                      │
  │                                      ▼
  └──> security groups ──────────> EKS cluster ──> OIDC provider ──> IRSA roles
                                        │                                │
                                        ▼                                │
                                   node group ◄──── node IAM role        │
                                        │                                │
                                        ▼                                ▼
                              coredns, metrics-server, ebs-csi-driver ◄──┘

ECR repos ──> IAM policy for Jenkins   (independent branch, runs in parallel)
```

The whole apply takes 12-15 minutes, and roughly 10 of those are the control
plane. That wait is normal, not a hang.

---

## 10. What each command actually does

| Command | What happens |
|---------|--------------|
| `terraform init` | Downloads providers into `.terraform/`, configures the backend, writes `.terraform.lock.hcl` |
| `terraform fmt -recursive` | Reformats to canonical style. Run it before committing |
| `terraform validate` | Checks syntax and references. Does *not* call AWS, so it works offline |
| `terraform plan -out=tfplan` | Reads real AWS state, diffs against your code, saves the exact actions |
| `terraform apply tfplan` | Executes that saved plan. Applying a saved plan means no surprises between plan and apply |
| `terraform output` | Prints the outputs from state |
| `terraform destroy` | Deletes everything in this state file, in reverse dependency order |

**Why `plan -out` then `apply <file>` instead of a bare `apply`?** A bare apply
re-plans, so what it does may differ from what you reviewed if something changed
in between. Applying a saved plan file is what you would do in a pipeline, and
it is what your Sprint 2 Jenkins job will do.

---

## 11. Questions you should be able to answer

Work through these out loud. If you stumble, go back to the section named.

1. Why does `bootstrap/` keep its state locally instead of in S3? (§3)
2. What breaks if the `kubernetes.io/role/elb` subnet tag is missing? (§4)
3. What is the difference between an Internet Gateway and a NAT Gateway? (§4)
4. Why `for_each` for ECR repos but `count` for subnets? (§2)
5. What is IRSA, and what would you have to do without it? (§7)
6. Why does the node group need an explicit `depends_on`? (§7)
7. What does `ignore_changes` on `desired_size` prevent? (§7)
8. Why can't the backend block use variables? (§8)
9. Name three cost decisions in this code and their approximate savings. (§4, §5, and `cost-optimization.md`)
10. How does Jenkins authenticate to AWS and to Kubernetes, without any stored
    access keys? (§6 and §7 step 8)

---

## 12. If you want to go deeper

The two ideas here that transfer to any real DevOps job are **remote state with
locking** (§3) and **IRSA / workload identity** (§7). Almost every other
concept in this folder is AWS-specific plumbing you can look up. Those two are
architectural patterns you will meet again on every cloud.
