# Terraform from zero - your workstream explained

Written assuming no prior AWS or Terraform knowledge. Four parts:

1. What Terraform is, and why each piece of AWS is in your task list
2. Why this folder looks the way it does
3. `resource`, `variable`, `output` - what each keyword means
4. Why this many of them, and not fewer

---

# Part 1 - What you are actually building

## What is Terraform?

Cloud resources can be created two ways.

**By clicking.** Log into the AWS console, click "Create VPC", fill a form,
click "Create cluster", fill another form. This works, and it is how most people
start. Three problems: you cannot repeat it reliably, nobody can review what you
did, and when you need to delete it all you have to remember every single thing
you clicked.

**By writing it down.** You describe the infrastructure you want in files.
Terraform reads those files, compares them to what actually exists in AWS, and
makes reality match your description. This is called **Infrastructure as Code**.

The practical difference:

| | Clicking | Terraform |
|---|---|---|
| Build it again next month | click through everything again | `terraform apply` |
| Show a teammate what exists | screenshots | read the files |
| Delete everything cleanly | hunt for leftovers | `terraform destroy` |
| Review before it happens | not possible | `terraform plan` |
| Track changes over time | not possible | git history |

Your entire workstream is one sentence: **describe the AWS infrastructure this
project needs, so it can be built, shared, and destroyed with a single command.**

## Why each AWS service is in your task list

The app is **ShopNow** (https://github.com/banalasusmitha/shopNow) - a MERN
e-commerce app split into three containers, plus a database:

| Container | What it is | Port |
|-----------|-----------|------|
| `frontend` | React storefront, served by nginx | 80 |
| `admin` | React admin dashboard, served by nginx | 80 |
| `backend` | Express API (products, orders, invoices) | 5000 |
| `mongodb` | the database the backend reads and writes | 27017 |

The first three are your team's code and get built into Docker images. MongoDB
uses the official public image - nobody builds it.

To run that on AWS you need five things, and each one is on your task list for
a reason.

### VPC - the private network

**What it is.** A Virtual Private Cloud is your own isolated network inside AWS.
Think of AWS as an enormous building; a VPC is your floor, with its own walls,
corridors and door.

**Why you need one.** Every EC2 instance and every Kubernetes node has to live
in a network. Without a VPC there is nowhere to put them. AWS gives every account
a "default VPC", and tutorials often use it - but it is shared with everything
else in the account, has no private subnets, and cannot be recreated if damaged.
Real projects build their own.

**What is inside a VPC:**

- **Subnets** - smaller sections of the network. You have four: two *public*
  (reachable from the internet) and two *private* (not reachable). They are
  spread across two Availability Zones, which are physically separate data
  centres, so one failing does not take everything down.
- **Internet Gateway** - the door to the internet. Without one, nothing in the
  VPC can reach anything outside.
- **NAT Gateway** - a one-way door. Things in private subnets can reach out
  (to download software, to pull images), but nothing outside can reach in.
- **Route tables** - the signposts telling traffic which door to use.
- **Security groups** - firewalls. "Allow port 22 from my IP only."

**Why public *and* private?** The Kubernetes worker nodes run your app. If they
sat in public subnets, anyone on the internet could try to reach them directly.
Putting them in private subnets means the only way in is through the load
balancer you deliberately expose. The NAT Gateway still lets them fetch what
they need.

### ECR - the image storage

**What it is.** Elastic Container Registry. A private storage service for Docker
images.

**Why you need one.** Avinash builds the app into Docker images. Those images
have to live somewhere the cluster can download them from. Docker Hub is public -
you would be publishing the project's code to the world. ECR is private to your
AWS account.

**Why three repositories?** One per service: frontend, admin, backend. Each is a
separate image with its own versions. MongoDB does not need one because it uses
the official public `mongo` image - nobody builds that.

**What your Terraform adds beyond just creating them:** scan-on-push (checks
images for known vulnerabilities), and a lifecycle policy that deletes old
images automatically. Without that policy, every Jenkins build adds around
300 MB that nothing ever cleans up.

### EKS - the Kubernetes cluster

**What it is.** Elastic Kubernetes Service. AWS runs Kubernetes for you.

**Why you need Kubernetes at all.** You could run the containers directly on an
EC2 server with `docker run`. That works until the server reboots and nothing
comes back, or traffic doubles and you need a second copy, or you deploy a new
version and the site goes down during the swap. Kubernetes handles all of that:
restarting crashed containers, running several copies, replacing them one at a
time during a deploy.

**Why EKS instead of installing Kubernetes yourself.** Kubernetes has two parts:
the **control plane** (the brain that decides what runs where) and the **worker
nodes** (the machines that actually run containers). The control plane is
genuinely hard to install and keep healthy. EKS runs it for you for about
$0.10/hour. You only manage the nodes.

**What your Terraform creates:**

- The control plane
- A **managed node group** - two EC2 instances that join the cluster as workers
- **Add-ons** - small pieces of software every cluster needs:
  - `vpc-cni` gives each pod a real network address
  - `coredns` lets pods find each other by name
  - `kube-proxy` handles internal networking
  - `aws-ebs-csi-driver` lets pods request disk storage (MongoDB needs this)
  - `metrics-server` reports CPU usage (autoscaling needs this)

### IAM - the permissions

**What it is.** Identity and Access Management. AWS's system for "who is allowed
to do what".

**Why you need it.** Three different things in this project need AWS permissions,
and none of them is a person:

- The **EKS control plane** needs permission to create network interfaces
- The **worker nodes** need permission to join the cluster and download images
  from ECR
- **Jenkins** needs permission to push images to ECR and deploy to the cluster

Each gets an IAM **role** - a set of permissions that a machine assumes, rather
than a username and password.

**Why this matters more than it sounds.** The alternative is creating an access
key (a long secret string) and pasting it into Jenkins. That secret then sits on
a server forever, and anyone who reads it has your AWS account. A role attached
to the machine gives temporary credentials that rotate automatically and cannot
be copied off. Your Terraform sets this up so Kaushik can delete the two
credentials currently in his Jenkinsfile.

### S3 remote state - the shared record

**What it is.** Terraform keeps a file called the **state file** that records
everything it has created - every resource ID, every setting. This is how it
knows, next time you run it, what already exists.

**Why it cannot just live on your laptop.** Four people share this project. If
the state file is only on your machine:

- Nobody else can run Terraform without creating duplicate resources
- If your laptop dies, nothing knows what exists in AWS, and cleanup becomes
  manual archaeology

So it goes in an **S3 bucket** that everyone can reach, with:

- **Versioning** - every previous version is kept, so a corrupted state can be
  rolled back
- **Encryption** - state files contain resource IDs and sometimes secrets
- **Locking** - if two people run `apply` simultaneously, the second one waits
  instead of both writing at once and corrupting the file

Your project brief lists this explicitly: *"Store Terraform state files securely
in AWS S3 for consistent multi-user access."*

## How the five fit together

```
        IAM ─────── permissions for everything below
         │
        VPC ─────── the network everything lives in
         │
        EKS ─────── cluster inside the VPC, nodes in private subnets
         │
        ECR ─────── images the cluster downloads and runs
         │
   S3 state ─────── the record of all of the above
```

---

# Part 2 - Why the folder looks like this

```
terraform-Sushmita/
├── bootstrap/       creates the S3 state bucket. Run once.
├── modules/         reusable building blocks
│   ├── vpc/
│   ├── ecr/
│   ├── iam/
│   └── eks/
├── envs/dev/        the stack you apply and destroy
├── extras/          a Kubernetes file the cluster needs after creation
└── docs/            written explanations
```

## Why `bootstrap/` is separate

A chicken-and-egg problem. You want Terraform state stored in S3. But creating
that S3 bucket is itself a Terraform action, which would need somewhere to store
*its* state - and the bucket does not exist yet.

The solution is one small stack that keeps its state in a plain local file and
creates the bucket everything else uses. You run it once and essentially never
again.

## Why `modules/` exists instead of one big file

You could put all 700 lines in one file. It would work. Two reasons not to:

**Reuse.** A module is like a function. `modules/vpc` describes *how* to build a
VPC without saying what size or where. When you add a `prod` environment later,
it calls the same module with different numbers. Both environments are then
guaranteed to be built the same way.

**Finding things.** With one file, changing the node count means scrolling
through VPC and IAM code to find it. With modules, everything about the network
is in one folder, everything about the cluster in another.

## Why `envs/dev/` exists

This is where the actual values live. `modules/vpc` says "I need a CIDR block";
`envs/dev/terraform.tfvars` says "it is `10.0.0.0/16`".

Splitting them means the *how* and the *what* are separate. Adding a production
environment is then a copy of one small folder, not a copy of everything.

**In practice you edit exactly one file day to day: `envs/dev/terraform.tfvars`.**

## Why `extras/` exists

`storageclass-gp3.yaml` is a Kubernetes file, not a Terraform file. EKS does not
ship a default StorageClass, so MongoDB's storage request would never be
fulfilled. Terraform installs the storage *driver*; this file tells Kubernetes
how to use it. It lives here because it is the last piece of the storage setup,
which is infrastructure.

---

# Part 3 - `resource`, `variable`, `output`

Three keywords do most of the work. Here is the difference.

## `resource` - "create this thing"

```hcl
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}
```

This is the only one that creates anything in AWS. Everything else is plumbing.

Reading the syntax:

- `resource` - the keyword
- `"aws_vpc"` - the **type**. Fixed vocabulary defined by AWS. You cannot invent
  `aws_my_thing`; look it up in the provider documentation.
- `"this"` - the **name you chose**. Internal to Terraform, never seen in AWS.
  Used to refer to it elsewhere: `aws_vpc.this.id`.
- Inside the braces - the settings.

**Tip.** Name it `"this"` when a module creates only one of that type, and
something descriptive when there are several - `aws_subnet.public` and
`aws_subnet.private`. Do not name it after its purpose *and* its type
(`aws_vpc.main_vpc` is redundant; `aws_vpc.main` is fine).

## `variable` - "an input someone gives me"

```hcl
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}
```

Creates nothing. It declares that this folder *accepts* a value called
`vpc_cidr`, which the code then refers to as `var.vpc_cidr`.

- `type` - `string`, `number`, `bool`, `list(string)`, `map(string)`. Terraform
  rejects a wrong type immediately instead of failing halfway through an apply.
- `default` - makes it optional. **No default means required** - Terraform
  refuses to run until it is supplied.
- `description` - shows up in error messages and documentation. Always write it.

**Tip.** Make something a variable if it might differ between environments
(region, sizes, names) or if it might need changing under pressure. Keep it
hard-coded if changing it would break the design - `enable_dns_support = true`
on the VPC is required by EKS, so exposing it as a variable would only offer
people a way to break the cluster.

## `output` - "a value I hand back"

```hcl
output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}
```

Creates nothing. It publishes a value so someone else can use it.

Two different audiences:

- **In a module** - so the calling code can use it. `modules/vpc` outputs the
  subnet IDs so `envs/dev/main.tf` can pass them to the EKS module. Without the
  output block, the value is trapped inside the module even though the subnets
  exist.
- **In `envs/dev`** - so a *person* can read it. Nothing calls `envs/dev`, so
  these are what `terraform output` prints for you to send to your teammates.

**Tip.** If you find yourself asking a teammate "what was the cluster name
again?", that is a missing output.

## Side by side

| | Creates AWS resources? | Direction | Referenced as |
|---|---|---|---|
| `resource` | yes | - | `aws_vpc.this.id` |
| `variable` | no | value comes **in** | `var.vpc_cidr` |
| `output` | no | value goes **out** | `module.vpc.vpc_id` |

## The full journey of one value

```
terraform.tfvars      vpc_cidr = "10.0.0.0/16"      ← you set it
envs/dev/variables.tf variable "vpc_cidr" {}        ← environment accepts it
envs/dev/main.tf      vpc_cidr = var.vpc_cidr       ← passed to the module
modules/vpc/variables.tf  variable "vpc_cidr" {}    ← module accepts it
modules/vpc/main.tf   cidr_block = var.vpc_cidr     ← used to create the VPC
                                                       ↓
                                              AWS creates the VPC
```

Five files for one value. Heavy for a small project - and exactly right once
there are two environments, because the bottom two files are shared and cannot
drift apart.

---

# Part 4 - Why this many resources?

Roughly 50 resources, 30 variables, 15 outputs. Reasonable questions: why not
fewer? Why not more?

## Why not fewer resources?

Almost all of them are **required by AWS**, not chosen for style. A VPC without
subnets holds nothing. Subnets without route tables cannot send traffic anywhere.
An EKS cluster without an IAM role will not start - AWS rejects the API call.

The genuinely optional ones are few:

| Resource | Could you drop it? | What breaks |
|---|---|---|
| NAT Gateway | yes | nodes must move to public subnets - cheaper, less secure |
| Private subnets | yes | everything becomes internet-facing |
| Second AZ | no | EKS refuses to create a cluster with subnets in only one AZ |
| ECR lifecycle policies | yes | storage grows forever, costs creep up |
| CloudWatch log group | yes | no control plane logs, and default retention is forever |
| SSM policy on nodes | yes | no way to get a shell on a private node |
| metrics-server | yes | the HPA in Sprint 4 cannot function |
| EBS CSI driver | yes | MongoDB's storage request is never fulfilled |

So around 45 of the 50 are mandatory. The rest were added because a specific part
of this project needs them.

**A concrete count.** The VPC alone is 20 resources: 1 VPC, 1 internet gateway,
4 subnets, 1 elastic IP, 1 NAT gateway, 3 route tables, 4 route table
associations, 2 routes, 2 security groups. None is optional if you want public
and private subnets across two AZs. That is simply what a VPC is made of.

## Why not more resources?

Deliberately left out, because a capstone does not need them:

- **VPC endpoints** - would keep ECR traffic off the NAT Gateway. Saves data
  charges at scale, adds ~$7/month each here. Not worth it.
- **Cluster Autoscaler / Karpenter** - adds nodes automatically under load. Your
  node group has a fixed range of 2-4 instead.
- **AWS Load Balancer Controller** - the project uses the NGINX ingress
  controller instead.
- **A second environment** - the structure supports it; only `dev` was needed.
- **Secrets Manager** - the app has no real secrets yet.
- **CloudWatch alarms** - Ravi's Prometheus covers monitoring.

Each would be defensible. Each is also more to explain and more to go wrong.

## Why this many variables?

The rule used: **something is a variable if a reasonable person might want it
different.**

Region, cluster name, node size, node count, CIDR block, whether to use Spot -
all vary by environment or by preference. So they are variables.

Things like `enable_dns_hostnames = true` on the VPC are hard-coded, because EKS
requires them. Making them configurable would only give someone a way to break
the cluster while appearing to offer choice.

**The failure mode in both directions.** Too few variables and you have to edit
module code to change a node size, which means `dev` and `prod` slowly become
different. Too many and the configuration becomes unreadable - fifty knobs where
five would do, and nobody knows which ones matter.

Roughly 30 variables across four modules is about seven each. That is normal for
modules of this size.

## Why this many outputs?

Each output exists because **somebody needs that specific value.**

| Output | Who needs it |
|---|---|
| `jenkins_instance_profile_name` | Kaushik, to attach to the Jenkins EC2 |
| `jenkins_security_group_id` | Kaushik, when launching the instance |
| `public_subnet_ids` | Kaushik, to choose where it goes |
| `ecr_repository_urls` | Avinash and Kaushik, for build and deploy |
| `cluster_name` | everyone, for `kubectl` access |
| `private_subnet_ids` | Ravi, to know where nodes run |
| `docker_build_args` | Avinash, so he does not forget `USER_NAME` |
| `kubeconfig_command` | anyone, so nobody has to remember the syntax |

Delete an output and someone has to log into the AWS console to look up a value.
Add pointless ones and `terraform output` becomes noise nobody reads.

**The test for adding one:** has anybody asked for this value, or would they have
to go hunting for it? If yes, it is an output.

---

# The short version

**What you built:** a private network, a container registry, a Kubernetes
cluster, the permissions to use them, and a shared record of it all - described
in code so it can be rebuilt or destroyed with one command.

**Why the folder is split three ways:** `bootstrap` solves a chicken-and-egg
problem, `modules` are reusable recipes, `envs/dev` supplies the actual values.

**Three keywords:** `resource` creates, `variable` takes a value in, `output`
sends a value back out.

**Why this size:** roughly 90% of the resources are required by AWS. The rest
were added because a specific part of this project needs them, and each optional
one has a reason you can state out loud.
